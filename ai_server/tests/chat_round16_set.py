"""Round 16 (9 Oct, PC): what users will ask about the account and posture features added later on 9 Oct:
change password from Profile (current password), the 3-day session, reminder days / the health-log
reminder / deleting a reminder, Exit on the posture screens, the Google account setup and the linked
message, the 5-wrong-codes limit, and plans that may now be followed together (clash by joints).
Written before changing the rules; the first run is the honest score: 9/30. Rules 3.45 added
change_password, session_expired, health_log_reminder, exit_exercise and google_setup and widened
reminders_help, verification_code and multiple_plans: 30/30. Checked not to take over: "how do i log out",
"exit" alone (goodbye), "my knee hurts when i stop halfway" (pain), "sharp pain every time ...".
"""
from chat_round1_set import KNEE
from chat_round4_set import SHOULDER

ROUND16 = [
    # change password from Profile
    (KNEE, "how do i change my password", "change_password"),
    (KNEE, "i want a new password but i still know the old one", "change_password"),
    (KNEE, "where to change password in profile", "change_password"),
    (KNEE, "it says the current password you entered is incorrect", "change_password"),
    (KNEE, "i forgot my password", "forgot_password"),
    (KNEE, "macam mana nak tukar kata laluan", "change_password"),
    # the 3-day session
    (KNEE, "why was i logged out", "session_expired"),
    (KNEE, "the app logged me out by itself", "session_expired"),
    (KNEE, "why do i need to log in again after a few days", "session_expired"),
    (KNEE, "do i have to log in every time i open the app", "session_expired"),
    # reminders
    (KNEE, "how do i change the days of my reminder", "reminders_help"),
    (KNEE, "can i get a reminder to log my blood pressure", "health_log_reminder"),
    (KNEE, "remind me to record my health readings", "health_log_reminder"),
    (KNEE, "how do i delete a reminder", "reminders_help"),
    (KNEE, "why cant i turn off the last day", "reminders_help"),
    (KNEE, "i only want reminders on weekdays", "reminders_help"),
    (KNEE, "why is there no delete button on my plan reminder", "reminders_help"),
    # Exit on the posture screens
    (KNEE, "how do i stop the exercise halfway", "exit_exercise"),
    (KNEE, "how do i exit the recording", "exit_exercise"),
    (KNEE, "i want to quit the exercise and go back home", "exit_exercise"),
    (KNEE, "if i exit will my result be saved", "exit_exercise"),
    # Google account setup
    (KNEE, "i signed in with google why does it ask for a password", "google_setup"),
    (KNEE, "why do i need a username after google sign in", "google_setup"),
    (KNEE, "what happens if i cancel the account setup", "google_setup"),
    (KNEE, "it says my google account has been linked", "google_setup"),
    (KNEE, "can i log in with my email after using google", "google_setup"),
    # five wrong codes
    (KNEE, "i typed the wrong code many times", "verification_code"),
    (KNEE, "it says the code has expired but i just got it", "verification_code"),
    # plans that may be followed together
    (SHOULDER, "can i follow a shoulder plan and a hand plan together", "multiple_plans"),
    (SHOULDER, "why does my hand plan not clash with my shoulder plan", "multiple_plans"),
]
