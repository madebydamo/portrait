// Intro animation methods for Terminal class

Terminal.prototype.startIntroAnimation = function() {
  const introText = [
    "Welcome to my Portfolio Website^5",
    "Welcome to my Portfolio Terminal^500",
    "Connecting...^1000",
    "Type 'help' to see available commands.",
  ];

  new Typed("#typed-intro", {
    strings: introText,
    typeSpeed: 10,
    backSpeed: 7,
    fadeOut: false,
    smartBackspace: true,
    loop: false,
    showCursor: true,
    cursorChar: "_",
    onComplete: () => {
      setTimeout(() => {
        this.showCommand("help");
        setTimeout(() => {
          this.loadCommand("help");
          // Ensure input gets focus after intro completes
          setTimeout(() => {
            if (this.inputLine.style.display !== "none") {
              this.input.focus();
            }
          }, 200);
        }, 500);
      }, 1000);
    },
  });
};

Terminal.prototype.showCommand = function(command) {
  const commandLine = document.createElement("div");
  commandLine.innerHTML = `<span class="prompt">damo@portfolio:~$ </span>${command}`;
  this.output.appendChild(commandLine);
};