# Using Aroyn

The public home page can be opened without signing in. Its dashboard screenshot uses illustrative data. All dashboard sections require sign-in. Choose **Open dashboard → Sign in with Discord**, then open **Runtime**. After signing in, generate a dashboard key from the account/avatar menu if one does not already exist.

In Aroyn Hub, open **Session** and enter that dashboard key to link the running client. Return to **Dashboard → Runtime** to view the connection state and live telemetry. Other dashboard sections show activity, inventory, statistics, configuration, and modules when corresponding data is available.

Treat the dashboard key like a password. Do not post it in issues, screenshots, or chat. If the dashboard remains disconnected, check that the client is running, the key was entered correctly, and the API and live Worker addresses match the deployment you are using.

Aroyn is the new name for the former Veyra Hub. The legacy loader shows the migration notice.

Open your avatar menu → **Account data** to download your account's data or delete the Aroyn account. Deletion requires a Discord sign-in within the last 15 minutes and typing `DELETE`; it revokes every Aroyn session/key. It does not delete your Discord or Roblox accounts. History expires after 30 days without updates, snapshots after 7 days; cleanup runs daily. See [data scope and limits](account-data.md).

This source package includes the readable Roblox client and stable loader. The steps above describe the existing product interface; they do not make the static dashboard preview alone a working live service. For running your own backend, see [local setup](setup.md).

## Updated client launch

The [homepage](https://aroyn-staging.pages.dev/) provides **Copy launch script** and a manual **View launch command** fallback. It copies a command without executing it in the browser. See [client release](client-release.md) for compatible game, endpoints and migration. The [status page](https://aroyn-staging.pages.dev/status/) checks only HTTP availability. Owner analytics uses `/admin/` and server authorization. Public beta sign-in is open through Discord; account data remains private.

## Mobile screens and pet feeding

Version 4.3.90 uses scrolling tabs and a single-column layout on small screens. In **Pets**, enable **Auto Feed** to start below 25% hunger and stop at 80%. It uses the cheapest eligible inventory or own-plot fruit, skipping favorites and locked/waxed fruit. **Max fruit value** sets a price cap; 0 means no cap. Feeding defaults off. See [behavior and verification](mobile-pet-feeding.md).
