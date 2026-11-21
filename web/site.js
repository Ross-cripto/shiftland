const copyButton = document.querySelector(".copy");
const commands = document.querySelector("#install-commands");
const copyStatus = document.querySelector("[data-copy-status]");

if (navigator.clipboard) {
  copyButton.hidden = false;
  copyButton.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(commands.textContent);
      copyButton.textContent = "Copied";
      copyStatus.textContent = "Build commands copied.";
    } catch {
      copyButton.textContent = "Select and copy";
      copyStatus.textContent = "Clipboard unavailable. Select the commands to copy them.";
    }
  });
}

const demo = document.querySelector("#workspace-demo");
const playButton = document.querySelector(".demo-play");

function showVideoControls() {
  demo.controls = true;
  if (document.activeElement === playButton) demo.focus();
  playButton.hidden = true;
}

demo.controls = false;
playButton.hidden = false;
playButton.addEventListener("click", async () => {
  try {
    await demo.play();
  } catch {
    showVideoControls();
  }
});
demo.addEventListener("play", showVideoControls, { once: true });
