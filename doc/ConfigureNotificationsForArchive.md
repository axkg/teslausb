OPTIONAL: You can choose to integrate with [Pushover](https://pushover.net), [Gotify](https://gotify.net/), [IFTTT](https://ifttt.com), [Telegram](https://telegram.org) and/or [AWS SNS](https://aws.amazon.com/sns/) to get a push/email notification to your phone when the copy process is done. Depending on your wireless network speed/connection, copying files may take some time, so a push notification can help confirm that the process finished. If no files were copied (i.e. all manually saved dashcam files were already copied, no notification will be sent.).

# Pushover
The Pushover service is free for up to 7,500 messages per month, but the [iOS](https://pushover.net/clients/ios)/[Android](https://pushover.net/clients/android) apps do have a one time cost, after a free trial period. *This also assumes your Pi is connected to a network with internet access.*

1. Create a free account at Pushover.net, and install and log into the mobile Pushover app.
1. On the Pushover dashboard on the web, copy your **User key**.
1. [Create a new Application](https://pushover.net/apps/build) at Pushover.net. The description and icon don't matter, choose what you prefer.
1. Copy the **Application Key** for the application you just created. The User key + Application Key are basically a username/password combination to needed to send the push.
1. Run these commands, substituting your user key and app key in the appropriate places. No `"` are needed.
    ```
    export PUSHOVER_ENABLED=true
    export PUSHOVER_USER_KEY=put_your_userkey_here
    export PUSHOVER_APP_KEY=put_your_appkey_here
    ```

# Gotify
Gotify is a self-hosted notification service. The android client is available on [Google Play](https://play.google.com/store/apps/details?id=com.github.gotify), [F-Droid](https://f-droid.org/de/packages/com.github.gotify/), or a standalone [APK](https://github.com/gotify/android/releases/latest).

1. Install server by following [instructions](https://gotify.net/docs/install)
1. [Create a new Application](https://gotify.net/docs/pushmsg)
1. Copy the app's token
1. Run these commands, substituting your domain and app token in the appropriate places.
    ```
    export GOTIFY_ENABLED=true
    export GOTIFY_DOMAIN=https://gotify.domain.com
    export GOTIFY_APP_TOKEN=put_your_token_here
    export GOTIFY_PRIORITY=5
    ```

# IFTTT
IFTTT is a completely free alternative that can be configured to send notifications. It requires an account and the IFTTT app to be installed but is available for both [iOS](https://itunes.apple.com/app/apple-store/id660944635) and [Android](https://play.google.com/store/apps/details?id=com.ifttt.ifttt).

1. Connect the [Webhooks service](https://ifttt.com/maker_webhooks)
1. Create a new applet
    1. Choose "Webhooks" as the service
    1. Choose "Receive a web request" as the trigger
    1. Provide a unique **Event Name** to create the trigger and note this down
    1. Choose "Notifications" as the action service
    1. Choose "Send a notification from the IFTTT app" as the action
    1. Customize the message to be something like
        ```
        {{Value1}} {{Value2}} {{Value3}} ({{OccurredAt}})
        ```
        - `Value3` will not be used by `teslausb`
        - Feel free to modify this later to your liking.
    1. Name and save the applet. You can modify the name, event name, and message by clicking on the Gear icon.
1. Test the applet out by going back to the [Webhooks service](https://ifttt.com/maker_webhooks) page and clicking on "Documentation".
1. Note down the **key**.
1. Trigger the test by providing the event name and optional values 1-3.
1. If it's not working, you can try to run the curl command manually via your command line and it should return a more informative error message. You can also try to generate a new **key** by going to the [Webhooks settings](https://ifttt.com/services/maker_webhooks/settings) page, and clicking "Edit Connection".
1. You should receive a notification within a few seconds. :)
1. Run these commands, substituting your event name and key in the appropriate places.
    ```
    export IFTTT_ENABLED=true
    export IFTTT_EVENT_NAME=put_your_event_name_here
    export IFTTT_KEY=put_your_key_here
    ```

# AWS SNS
You can also choose to send notification through AWS SNS. You can create a free AWS account and the free tier enables you to receive notifications via SNS for free.

1. Create a free account at [AWS](https://aws.amazon.com/).
1. Create a user in IAM and give it the rights to SNS.
1. Create a new SNS topic.
1. Create the notification end point (email or other)
1. Run these commands, substituting your user key and app key in the appropriate places. Use of `"` is required for AWS_SNS_TOPIC_ARN.
    ```
    export SNS_ENABLED=true
    export AWS_REGION=us-east-1
    export AWS_ACCESS_KEY_ID=put_your_accesskeyid_here
    export AWS_SECRET_ACCESS_KEY=put_your_secretkey_here
    export AWS_SNS_TOPIC_ARN=put_your_sns_topicarn_here
    ```

# Webhook
Generic Webhook call can be used with Node-Red, [Home-Assistant](https://home-assistant.io), and other self hosted automation systems.

1. Setup webhook url with your provider
2. Run these commands, substituting your url.
    ```
    export WEBHOOK_ENABLED=true
    export WEBHOOK_URL=http://domain/path
    ```

# Telegram
You can choose to send notifications via [Telegram](https://telegram.org/). This is a completely free alternative, but you need Telegram app (also free) on your device. It is available for iOS as well as Android and other platforms. See the complete list [here](https://telegram.org/apps)

1. If you don't already have it, download the Telegram Client for your device [here](https://telegram.org/apps) and go through the sign up process. 
2. Once sign-up is complete, you can add [this](https://thereisabotforthat.com/bots/userinfobot) bot to your telegram client. 
3. Send any message (e.g. "Hi") to the bot and it will respond with your id. This identifies the recipient and is the value you will use for TELEGRAM_CHAT_ID
4. You will need to create a new bot that acts as a sender. Follow the instructions [here](https://www.siteguarding.com/en/how-to-get-telegram-bot-api-token) to get your bot token. 
5. If the API key does not have the "bot" prefix. Make sure you include it when entering TELEGRAM_BOT_TOKEN. 
6. Remove the comments and update the following values in the ```teslausb_setup_variables.conf``` file.
    ```
    export TELEGRAM_ENABLED=true
    export TELEGRAM_CHAT_ID=123456789
    export TELEGRAM_BOT_TOKEN=bot123456789:abcdefghijklmnopqrstuvqxyz987654321
    export TELEGRAM_SILENT_NOTIFY=false
    ```

# Matrix
Matrix is a federated messaging protocol that can be used via [Matrix.org](https://matrix.org) or self hosted homeservers. Matrix can be used via a web browser or one of the [many available clients](https://matrix.org/clients/).

1. Create an account for your bot on either on [matrix.org](https://matrix.org) or your own homeserver
2. Create a room where you want to send the notifications to, either as the bot user or invite and join the bot user to the room
3. Navigate to the room settings to discover the "Internal room ID"
4. Remove the comments and update the following values in the ```teslausb_setup_variables.conf``` file with the gathered information. Use of `'` is required for MATRIX_PASSWORD and MATRIX_ROOM:

    ```
    export MATRIX_ENABLED=true
    export MATRIX_SERVER_URL=https://matrix.org/
    export MATRIX_USERNAME=put_your_matrix_username_here
    export MATRIX_PASSWORD='put_your_matrix_password_here'
    export MATRIX_ROOM='put_the_matrix_target_room_id_here'
    ```
