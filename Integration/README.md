# Show local task activity in Lumo

1. Run the setup from the Xcode project folder.

   ```sh
   /usr/bin/python3 Integration/lumo_activity.py install
   ```

2. In the ChatGPT desktop app, open **Settings → Hooks**, review the Lumo hooks, and trust them. In the Codex CLI, use **`/hooks`**. The setup adds Lumo’s entries alongside any existing hooks.
3. Run Lumo, right-click it, and choose **Connect Task Activity…**. Select the **Activity** folder printed by setup.
4. Start a local Codex or local ChatGPT Work task as usual. Lumo shows the latest reported step and prioritizes questions and approval requests when several tasks are active. Reply in the original chat.

The relay keeps short status labels and project names in the selected folder on your Mac. Tool commands, chat text, and results stay in the original task. Some hosted tools report only general progress through local hooks. Cloud Work requires a workspace-managed integration.

Choose **Disconnect Task Activity** in Lumo to hide updates. To remove the relay from Codex, run `/usr/bin/python3 Integration/lumo_activity.py uninstall` from the project folder.

[OpenAI’s hooks documentation](https://learn.chatgpt.com/docs/hooks)
