// Intro animation methods for Terminal class

Terminal.prototype.startIntroAnimation = function () {
  const introText = [
    "Loading Virus....^100",
    "just kidding :)",
    "Type help to see available commands.",
  ];

  new Typed("#typed-intro", {
    strings: introText,
    typeSpeed: 10,
    backSpeed: 7,
    fadeOut: false,
    smartBackspace: true,
    loop: false,
    showCursor: false,
    cursorChar: "_",
    onComplete: () => {
      // Make 'help' clickable in the intro text
      const typedIntro = document.getElementById("typed-intro");
      typedIntro.innerHTML = typedIntro.innerHTML.replace(
        "Type help to see available commands.",
        'Type <span class="clickable-command" data-command="help">help</span> to see available commands.',
      );

      setTimeout(() => {
        this.showCommand("whoami");
        setTimeout(() => {
          this.loadCommand("whoami");
        }, 100);
      }, 300);
    },
  });
};

Terminal.prototype.showCommand = function (command) {
  const commandLine = document.createElement("div");
  commandLine.innerHTML = `<span class="prompt">damo@portfolio:~$ </span>${command}`;
  this.output.appendChild(commandLine);
};
