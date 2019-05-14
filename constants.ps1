# # mainly constants for .NET Schedule.Service for now.

## TaskFolder.RegisterTaskDefinition->flags

# The Task Scheduler checks the syntax of the XML that describes the task but
# does not register the task. This constant cannot be combined with the
# TASK_CREATE, TASK_UPDATE, or TASK_CREATE_OR_UPDATE values.
Set-Variable -Option Constant -Name TASK_VALIDATE_ONLY -Value 0x1

# The Task Scheduler registers the task as a new task.
Set-Variable -Option Constant -Name TASK_CREATE -Value 0x2

# The Task Scheduler registers the task as an updated version of an existing
# task. When a task with a registration trigger is updated, the task will
# execute after the update occurs.
Set-Variable -Option Constant -Name TASK_UPDATE -Value 0x4

# The Task Scheduler either registers the task as a new task or as an updated
# version if the task already exists. Equivalent to TASK_CREATE | TASK_UPDATE.
Set-Variable -Option Constant -Name TASK_CREATE_OR_UPDATE -Value 0x6

# The Task Scheduler disables the existing task.
Set-Variable -Option Constant -Name TASK_DISABLE -Value 0x8

# The Task Scheduler is prevented from adding the allow access-control entry
# (ACE) for the context principal. When the TaskFolder.RegisterTaskDefinition
# function is called with this flag to update a task, the Task Scheduler
# service does not add the ACE for the new context principal and does not
# remove the ACE from the old context principal.
Set-Variable -Option Constant -Name TASK_DONT_ADD_PRINCIPAL_ACE -Value 0x10

# The Task Scheduler creates the task, but ignores the registration triggers in
# the task. By ignoring the registration triggers, the task will not execute
# when it is registered unless a time-based trigger causes it to execute on
# registration.
Set-Variable -Option Constant -Name TASK_IGNORE_REGISTRATION_TRIGGERS -Value 0x20

## TaskFolder.RegisterTaskDefinition->logonType

# The logon method is not specified. Used for non-NT credentials. 
Set-Variable -Option Constant -Name TASK_LOGON_NONE -Value 0

# Use a password for logging on the user. The password must be supplied at
# registration time.
Set-Variable -Option Constant -Name TASK_LOGON_PASSWORD -Value 1

# Use an existing interactive token to run a task. The user must log on using a
# service for user (S4U) logon. When an S4U logon is used, no password is
# stored by the system and there is no access to either the network or to
# encrypted files.
Set-Variable -Option Constant -Name TASK_LOGON_S4U -Value 2

# User must already be logged on. The task will be run only in an existing
# interactive session.
Set-Variable -Option Constant -Name TASK_LOGON_INTERACTIVE_TOKEN -Value 3

# Group activation. The groupId field specifies the group.
Set-Variable -Option Constant -Name TASK_LOGON_GROUP -Value 4

# Indicates that a Local System, Local Service, or Network Service account is
# being used as a security context to run the task.
Set-Variable -Option Constant -Name TASK_LOGON_SERVICE_ACCOUNT -Value 5

# First use the interactive token. If the user is not logged on (no interactive
# token is available), then the password is used. The password must be
# specified when a task is registered. This flag is not recommended for new
# tasks because it is less reliable than TASK_LOGON_PASSWORD.
Set-Variable -Option Constant -Name TASK_LOGON_INTERACTIVE_TOKEN_OR_PASSWORD -Value 6


## ActionCollection.Create->type

# The action performs a command-line operation. For example, the action could
# run a script, launch an executable, or, if the name of a document is
# provided, find its associated application and launch the application with the
# document.
Set-Variable -option Constant -Name TASK_ACTION_EXEC -Value 0

# The action fires a handler.
Set-Variable -option Constant -Name TASK_ACTION_COM_HANDLER -Value 5

# This action sends email message.
Set-Variable -option Constant -Name TASK_ACTION_SEND_EMAIL -Value 6

# This action shows a message box.
Set-Variable -option Constant -Name TASK_ACTION_SHOW_MESSAGE -Value 7


## Trigger.Type

# Starts the task when a specific event occurs.
Set-Variable -Option Constant -Name TASK_TRIGGER_EVENT -Value 0

# Starts the task at a specific time of day.
Set-Variable -Option Constant -Name TASK_TRIGGER_TIME -Value 1

# Starts the task daily.
Set-Variable -Option Constant -Name TASK_TRIGGER_DAILY -Value 2

# Starts the task weekly.
Set-Variable -Option Constant -Name TASK_TRIGGER_WEEKLY -Value 3

# Starts the task monthly.
Set-Variable -Option Constant -Name TASK_TRIGGER_MONTHLY -Value 4

# Starts the task every month on a specific day of the week.
Set-Variable -Option Constant -Name TASK_TRIGGER_MONTHLYDOW -Value 5

# Starts the task when the computer goes into an idle state.
Set-Variable -Option Constant -Name TASK_TRIGGER_IDLE -Value 6

# Starts the task when the task is registered.
Set-Variable -Option Constant -Name TASK_TRIGGER_REGISTRATION -Value 7

# Starts the task when the computer boots.
Set-Variable -Option Constant -Name TASK_TRIGGER_BOOT -Value 8

# Starts the task when a specific user logs on.
Set-Variable -Option Constant -Name TASK_TRIGGER_LOGON -Value 9

# Triggers the task when a specific session state changes.
Set-Variable -Option Constant -Name TASK_TRIGGER_SESSION_STATE_CHANGE -Value 11

