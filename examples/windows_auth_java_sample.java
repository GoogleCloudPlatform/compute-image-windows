package sample;


import java.security.*;
import java.security.spec.*;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.LinkedList;
import java.util.List;
import java.util.TimeZone;

import javax.crypto.Cipher;

import java.math.BigInteger;

import com.google.api.client.auth.oauth2.Credential;
import com.google.common.io.BaseEncoding;

import org.json.simple.JSONObject;
import org.json.simple.parser.JSONParser;

import com.google.api.client.googleapis.auth.oauth2.GoogleCredential;
import com.google.api.services.compute.Compute;
import com.google.api.services.compute.model.Instance;
import com.google.api.services.compute.model.Metadata;
import com.google.api.services.compute.model.Metadata.Items;
import com.google.api.services.compute.model.SerialPortOutput;
import com.google.api.client.json.JsonFactory;
import com.google.api.client.json.jackson2.JacksonFactory;
import com.google.api.client.repackaged.org.apache.commons.codec.binary.Base64;
import com.google.api.client.http.HttpTransport;
import com.google.api.client.googleapis.javanet.GoogleNetHttpTransport;

public class ExampleCode {

  public ExampleCode() {}

  // Constants used to configure behavior
  private static final String ZONE_NAME = "us-central1-a";
  private static final String PROJECT_NAME = "example-project-1234";
  private static final String INSTANCE_NAME = "test-instance";
  private static final String APPLICATION_NAME = "windows-pw-reset";

  // Constants for configuring user name, email, and SSH key expiration
  private static final String USER_NAME = "example_user";
  private static final String EMAIL = "example_user@test.com";

  // Keys are one-time use, so the metadata doesn't need to stay around for long.
  // 5 minutes chosen to allow for differences between time on the client
  // and time on the server
  private static final long EXPIRE_TIME = 300000;

  // HttpTransport and JsonFactory used to create the Compute object
  private static HttpTransport httpTransport;
  private static final JsonFactory JSON_FACTORY = JacksonFactory.getDefaultInstance();



  public static void main(String[] args) {
    ExampleCode ec = new ExampleCode();
    try {
      // Initialize Transport object
      httpTransport = GoogleNetHttpTransport.newTrustedTransport();

      // Reset the password
      ec.resetPassword();
    } catch (Exception e) {
      e.printStackTrace();
      System.exit(1);
    }
  }

  public void resetPassword() throws Exception {
    // Get credentials to setup a connection with the Compute API
    Credential cred = GoogleCredential.getApplicationDefault();

    // Create an instance of the Compute API
    Compute compute = new Compute.Builder(httpTransport, JSON_FACTORY, null)
        .setApplicationName(APPLICATION_NAME).setHttpRequestInitializer(cred).build();

    // Get the instance object to gain access to the instance's metadata
    Instance inst = compute.instances().get(PROJECT_NAME, ZONE_NAME, INSTANCE_NAME).execute();
    Metadata metadata = inst.getMetadata();

    // Generate the public/private key pair for encryption and decryption
    KeyPair keys = generateKeys();

    // Update metadata from instance with new windows-keys entry
    replaceMetadata(metadata, buildKeyMetadata(keys));

    // Tell GCE to update the instance metadata with our changes
    compute.instances().setMetadata(PROJECT_NAME, ZONE_NAME, INSTANCE_NAME, metadata).execute();

    System.out.println("Updating metadata...");

    // Sleep while waiting for metadata to propagate - production code may
    // want to monitor the status of the metadata update operation
    Thread.sleep(30000);

    System.out.println("Getting serial output...");

    // Request the output from serial port 4
    // In production code, this operation should be polled
    SerialPortOutput output = compute.instances()
        .getSerialPortOutput(PROJECT_NAME, ZONE_NAME, INSTANCE_NAME).setPort(4).execute();

    // Get the last line - this will be a JSON string corresponding to the
    // most recent password reset attempt
    String[] entries = output.getContents().split("\n");
    String outputEntry = entries[entries.length - 1];

    // Parse output using the json-simple library
    JSONParser parser = new JSONParser();
    JSONObject passwordDict = (JSONObject) parser.parse(outputEntry);

    String encryptedPassword = passwordDict.get("encryptedPassword").toString();

    // Output user name and decrypted password
    System.out.println("\nUser name: " + passwordDict.get("userName").toString());
    System.out.println("Password: " + decryptPassword(encryptedPassword, keys));
  }

  private String decryptPassword(String message, KeyPair keys) {
    try {
      // Add the bouncycastle provider - the built-in providers don't support RSA
      // with OAEPPadding
      Security.addProvider(new org.bouncycastle.jce.provider.BouncyCastleProvider());

      // Get the appropriate cipher instance
      Cipher rsa = Cipher.getInstance("RSA/NONE/OAEPPadding", "BC");

      // Add the private key for decryption
      rsa.init(Cipher.DECRYPT_MODE, keys.getPrivate());

      // Decrypt the text
      byte[] rawMessage = Base64.decodeBase64(message);
      byte[] decryptedText = rsa.doFinal(rawMessage);

      // The password was encoded using UTF8. Transform into string
      return new String(decryptedText, "UTF8");
    } catch (Exception e) {
      e.printStackTrace();
      System.exit(1);
    }
    return "";
  }

  private void replaceMetadata(Metadata input, JSONObject newMetadataItem) {
    // Transform the JSON object into a string that the API can use
    String newItemString = newMetadataItem.toJSONString();

    // Get the list containing all of the Metadata entries for this instance
    List<Items> items = input.getItems();

    // If the instance has no metadata, items can be returned as null.
    if (items == null)
    {
      items = new LinkedList<Items>();
      input.setItems(items);
    }

    // Find the "windows-keys" entry and update it
    for (Items item : items) {
      if (item.getKey().compareTo("windows-keys") == 0) {
        // Replace item's value with the new entry.
        // To prevent race conditions, production code may want to maintain a
        // list where the oldest entries are removed once the 32KB limit is
        // reached for the metadata entry.
        item.setValue(newItemString);
        return;
      }
    }

    // "windows.keys" entry doesn't exist in the metadata - append it.
    // This occurs when running password-reset for the first time on an instance
    items.add(new Items().setKey("windows-keys").setValue(newItemString));
  }

  private KeyPair generateKeys() throws NoSuchAlgorithmException {
    KeyPairGenerator keyGen = KeyPairGenerator.getInstance("RSA");

    // Key moduli for encryption/decryption are 2048 bits long
    keyGen.initialize(2048);

    return keyGen.genKeyPair();
  }


  @SuppressWarnings("unchecked")
  private JSONObject buildKeyMetadata(KeyPair pair) throws NoSuchAlgorithmException,
      InvalidKeySpecException {
    // Object used for storing the metadata values
    JSONObject metadataValues = new JSONObject();

    // Encode the public key into the required JSON format
    metadataValues.putAll(jsonEncode(pair));

    // Add username and email
    metadataValues.put("userName", USER_NAME);
    metadataValues.put("email", EMAIL);

    // Create the date on which the new keys expire
    Date now = new Date();
    Date expireDate = new Date(now.getTime() + EXPIRE_TIME);

    // Format the date to match rfc3339
    SimpleDateFormat rfc3339Format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
    rfc3339Format.setTimeZone(TimeZone.getTimeZone("UTC"));
    String dateString = rfc3339Format.format(expireDate);

    // Encode the expiration date for the returned JSON dictionary
    metadataValues.put("expireOn", dateString);

    return metadataValues;
  }

  @SuppressWarnings("unchecked")
  private JSONObject jsonEncode(KeyPair keys) throws NoSuchAlgorithmException,
      InvalidKeySpecException {
    KeyFactory factory = KeyFactory.getInstance("RSA");

    // Get the RSA spec for key manipulation
    RSAPublicKeySpec pubSpec = factory.getKeySpec(keys.getPublic(), RSAPublicKeySpec.class);

    // Extract required parts of the key
    BigInteger modulus = pubSpec.getModulus();
    BigInteger exponent = pubSpec.getPublicExponent();

    // Grab an encoder for the modulus and exponent to encode using RFC 3548;
    // Java SE 7 requires an external library (Google's Guava used here)
    // Java SE 8 has a built-in Base64 class that can be used instead. Apache also has an RFC 3548
    // encoder
    BaseEncoding stringEncoder = BaseEncoding.base64();

    // Strip out the leading 0 byte in the modulus
    byte[] arr = Arrays.copyOfRange(modulus.toByteArray(), 1, modulus.toByteArray().length);

    JSONObject returnJson = new JSONObject();

    // Encode the modulus, add to returned JSON object
    String modulusString = stringEncoder.encode(arr).replaceAll("\n", "");
    returnJson.put("modulus", modulusString);

    // Encode exponent, add to returned JSON object
    String exponentString = stringEncoder.encode(exponent.toByteArray()).replaceAll("\n", "");
    returnJson.put("exponent", exponentString);

    return returnJson;
  }

}
