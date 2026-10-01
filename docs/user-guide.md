# Using Aroyn

The public home page can be opened without signing in. Its dashboard screenshot uses illustrative data. All dashboard sections require sign-in. Choose **Open dashboard → Sign in with Discord**, then open **Runtime**. After signing in, generate a dashboard key from the account/avatar menu if one does not already exist.

In the existing compatible Veyra Hub client, open **Session** and enter that dashboard key to link the running client. Return to **Dashboard → Runtime** to view the connection state and live telemetry. Other dashboard sections show activity, inventory, statistics, configuration, and modules when corresponding data is available.

Treat the dashboard key like a password. Do not post it in issues, screenshots, or chat. If the dashboard remains disconnected, check that the client is running, the key was entered correctly, and the API and live Worker addresses match the deployment you are using.

Aroyn is the new name for the same product. The current Roblox client still displays Veyra Hub.

Open your avatar menu → **Account data** to download your account's data or delete the Aroyn account. Deletion requires a Discord sign-in within the last 15 minutes and typing `DELETE`; it revokes every Aroyn session/key. It does not delete your Discord or Roblox accounts. History expires after 30 days without updates, snapshots after 7 days; cleanup runs daily. See [data scope and limits](account-data.md).

This source package does not include the Roblox client or a public installation method for it. The steps above describe the existing product interface; they do not make the static dashboard preview alone a working live service. For running your own backend, see [local setup](setup.md).
