Subject: Appeal to App Review Board - Tappy Keyboard Sounds 1.0 (38), Guideline 2.4.5(v)

Hello App Review Board,

I would like to appeal the rejection of Tappy Keyboard Sounds 1.0 (38), Submission ID d2d0985a-0c47-4946-b3eb-c872459566df, under Guideline 2.4.5(v).

The latest rejection states:

"The app requests Input Monitoring access from the user in order to enable keyboard sounds, which is not appropriate for apps on the Mac App Store."

I understand and respect Apple's concern around broad input permissions. However, I believe this rejection reflects inconsistent treatment of this app category on the Mac App Store, or a misunderstanding of Tappy's implementation and product behavior.

Tappy is a keyboard sound utility. Its user-facing purpose is to play local sound effects in response to physical keyboard activity. The app does not provide or advertise any hidden monitoring, automation, logging, analytics, or input-control behavior.

Technical implementation in build 1.0 (38):

- Tappy uses user-approved macOS Input Monitoring only for the disclosed keyboard sound feature.
- Tappy uses a listen-only CGEventTap.
- Tappy reads hardware key codes and modifier flags only to choose a local sound category, such as standard key, space, return, delete, or modifier.
- Tappy does not read typed characters or typed text.
- Tappy does not record, store, transmit, or analyze keystrokes.
- Tappy does not inject, modify, block, replace, or repost keyboard events.
- Tappy does not use Accessibility APIs such as AXIsProcessTrusted, AXIsProcessTrustedWithOptions, or AXUIElement.
- Tappy does not use NSEvent.addGlobalMonitorForEvents.
- Tappy does not install a custom keyboard or input source.
- Tappy is sandboxed.

The Mac App Store currently contains multiple apps with the same apparent product category and same user-facing need to observe keyboard activity for system-wide keyboard sounds. Examples include:

- Loud Typer: https://apps.apple.com/us/app/loud-typer/id1493508558?mt=12
- iTyper: https://apps.apple.com/us/app/ityper/id639594479?mt=12
- KeyBell - Mechanical Keyboard: https://apps.apple.com/us/app/keybell-mechanical-keyboard/id1530838633?mt=12
- Klack: https://apps.apple.com/us/app/klack/id6446206067
- Thock - Mechanical Keyboard: https://apps.apple.com/us/app/thock/id6757373836
- Keeby: https://apps.apple.com/us/app/keeby/id6760791739
- Klakk - Keyboard Sounds: https://apps.apple.com/us/app/klakk-keyboard-sounds/id6754638652?mt=12

These apps publicly describe behavior that appears materially equivalent to Tappy's core functionality: playing keyboard sounds across the Mac in response to keystrokes. At least one listing explicitly instructs users to grant Input Monitoring access so the app can capture keyboard events.

I am not submitting these examples to report other developers or request enforcement against them. I am citing them because they show that this product category appears to be accepted on the Mac App Store, and I am requesting consistent review treatment or specific technical guidance explaining the distinction.

Please either:

1. Reverse the rejection and approve Tappy 1.0 (38), or
2. Identify the specific technical or product distinction that makes the listed Mac App Store keyboard-sound apps acceptable while Tappy is not, so I can revise Tappy to comply with the same standard.

If Apple's current position is that any Mac App Store app whose primary feature is system-wide keyboard sound feedback may not request Input Monitoring, please confirm that explicitly so I can determine whether this product category is no longer eligible for Mac App Store distribution.

Thank you for reviewing this appeal.
