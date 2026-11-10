# GrokBot Desktop Pet

Lumo is a GrokBot-inspired desktop pet for macOS. It blinks and turns toward your cursor. You can customize its shape and color and connect it to local Codex or ChatGPT Work tasks.

## Run Lumo

1. Download or clone this repository on a Mac running macOS 15.6 or later.
2. Open `GrokBotPet.xcodeproj` in Xcode. The project was tested with Xcode 26.3.
3. Select the **GrokBotPet** scheme and **My Mac**, then press **⌘R**.

Lumo appears near the bottom-right corner on its first launch. Right-click it for all controls.

- **Customize Lumo…** lets you pick a shape, choose a preset color, or set your own color.
- **Move Lumo** lets you drag it. Choose **Lock Position** when you’re done.
- **Hide Lumo** hides it until you open the app again. **Quit Lumo** closes the app.

## Show task activity

The optional hook integration displays the current reported step of a local Codex or ChatGPT Work task in a bubble beside Lumo. If a task needs an answer or approval, Lumo shows a prompt to return to the original chat.

Follow the [task activity setup guide](Integration/README.md) to install the hooks and connect Lumo to the Activity folder.
