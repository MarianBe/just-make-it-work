# Renders docs/demo.gif — run from the repo root: vhs docs/demo.tape
Output docs/demo.gif

Set FontSize 15
Set Width 1000
Set Height 640
Set Theme "Dracula"
Set TypingSpeed 55ms
Set Shell bash
Set Padding 12

Hide
Type "source docs/demo-env.sh && clear"
Enter
Sleep 1s
Show

Type "bash install.sh"
Sleep 600ms
Enter

# orchestrator: intro renders, provider menu (github-copilot preselected)
Sleep 3s
Enter
# model menu, opus-4.8 preselected — wander a bit, come back, select
Sleep 1.5s
Down
Sleep 450ms
Down
Sleep 450ms
Up
Sleep 450ms
Up
Sleep 700ms
Enter

# worker: accept suggested provider + model (sonnet 5 preselected)
Sleep 2s
Enter
Sleep 1.2s
Enter

# setup: esc keeps the suggested default (haiku 4.5)
Sleep 2s
Escape

# summary + next steps
Sleep 5s
