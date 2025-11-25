// Command execution methods for Terminal class

Terminal.prototype.getTerminalWidthChars = function () {
  const terminal = document.getElementById("terminal");
  const style = getComputedStyle(terminal);
  const fontSize = parseFloat(style.fontSize);
  // Create a span to measure character width
  const span = document.createElement("span");
  span.textContent = "0";
  span.style.font = style.font;
  span.style.position = "absolute";
  span.style.visibility = "hidden";
  document.body.appendChild(span);
  const charWidth = span.offsetWidth;
  document.body.removeChild(span);
  const widthPx = terminal.offsetWidth;
  return Math.floor(widthPx / charWidth) - 4; //padding
};

Terminal.prototype.executeCommand = function (command) {
  this.showCommand(command);
  this.inputLine.style.display = "none";

  // Handle special commands
  if (command === "clear") {
    this.clearTerminal();
    return;
  }

  // Handle projects subcommands
  if (command.startsWith("projects ")) {
    const parts = command.split(" ");
    if (parts.length === 2) {
      const subcommand = parts[1];
      this.loadProjectSubcommand(subcommand);
      return;
    }
  }

  // Load command from commands directory
  this.loadCommand(command);
};

Terminal.prototype.loadProjectSubcommand = async function (subcommand) {
  const validSubcommands = ["rubiks", "uttt", "mandelbrot", "homeserver"];

  if (validSubcommands.includes(subcommand)) {
    try {
      // Load HTML content from commands directory
      const htmlResponse = await fetch(`/commands/${subcommand}.html`);
      if (htmlResponse.ok) {
        const htmlContent = await htmlResponse.text();
        const commandOutput = document.createElement("div");
        commandOutput.innerHTML = htmlContent;
        this.output.appendChild(commandOutput);
        // Execute any scripts in the loaded HTML
        const scripts = commandOutput.querySelectorAll('script');
        const container = commandOutput.querySelector('.message-container') || commandOutput.querySelector('div') || commandOutput;
        scripts.forEach(script => {
            if (script.src) {
                const newScript = document.createElement('script');
                newScript.src = script.src;
                document.head.appendChild(newScript);
            } else {
                const scriptText = script.textContent.replace('const container = document.currentScript.parentElement;', '');
                const scriptFunction = new Function('container', scriptText);
                scriptFunction(container);
            }
        });
      } else {
        const errorOutput = document.createElement("div");
        errorOutput.innerHTML = `<p class="output">Error loading project: ${subcommand}</p>`;
        this.output.appendChild(errorOutput);
      }
    } catch (error) {
      const errorOutput = document.createElement("div");
      errorOutput.innerHTML = `<p class="output">Error loading project: ${error.message}</p>`;
      this.output.appendChild(errorOutput);
    }
  } else {
    const errorOutput = document.createElement("div");
    errorOutput.innerHTML = `<p class="output">Unknown project: ${subcommand}. Available projects: rubiks, uttt, mandelbrot, homeserver</p>`;
    this.output.appendChild(errorOutput);
  }

  // Show prompt again after command execution
  setTimeout(() => {
    this.showPrompt();
    this.scrollToBottom();
  }, 100);
};

Terminal.prototype.loadCommand = async function (command) {
  // Check if command is available in the commands directory
  if (this.availableCommands.includes(command)) {
    try {
      // Load HTML content from commands directory
      const htmlResponse = await fetch(`/commands/${command}.html`);
      if (htmlResponse.ok) {
        const htmlContent = await htmlResponse.text();
        const commandOutput = document.createElement("div");
        commandOutput.innerHTML = htmlContent;
        this.output.appendChild(commandOutput);
        // Execute any scripts in the loaded HTML
        const scripts = commandOutput.querySelectorAll('script');
        const container = commandOutput.querySelector('.message-container') || commandOutput.querySelector('div') || commandOutput;
        scripts.forEach(script => {
            if (script.src) {
                const newScript = document.createElement('script');
                newScript.src = script.src;
                document.head.appendChild(newScript);
            } else {
                const scriptText = script.textContent.replace('const container = document.currentScript.parentElement;', '');
                const scriptFunction = new Function('container', scriptText);
                scriptFunction(container);
            }
        });
      } else {
        // This shouldn't happen if the command is in availableCommands, but fallback just in case
        const errorOutput = document.createElement("div");
        errorOutput.innerHTML = `<p class="output">Error loading command: ${command}</p>`;
        this.output.appendChild(errorOutput);
      }
    } catch (error) {
      const errorOutput = document.createElement("div");
      errorOutput.innerHTML = `<p class="output">Error loading command: ${error.message}</p>`;
      this.output.appendChild(errorOutput);
    }
  } else {
    // Command not in available commands - try executing as shell command
    try {
      const response = await fetch("/execute", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          command: command,
          width: this.getTerminalWidthChars(),
        }),
      });

      if (response.ok) {
        const data = await response.json();
        const commandOutput = document.createElement("div");

        if (data.stdout) {
          commandOutput.innerHTML = `<pre class="output">${ansiToHtml(data.stdout)}</pre>`;
        }

        if (data.stderr) {
          const stderrDiv = document.createElement("div");
          stderrDiv.innerHTML = `<pre class="output error">${ansiToHtml(data.stderr)}</pre>`;
          commandOutput.appendChild(stderrDiv);
        }

        this.output.appendChild(commandOutput);
      } else {
        // Command not found or error
        const errorOutput = document.createElement("div");
        errorOutput.innerHTML = `<p class="output">bash: ${command}: command not found</p>`;
        this.output.appendChild(errorOutput);
      }
    } catch (error) {
      const errorOutput = document.createElement("div");
      errorOutput.innerHTML = `<p class="output">Error executing command: ${error.message}</p>`;
      this.output.appendChild(errorOutput);
    }
  }

  // Show prompt again after command execution
  setTimeout(() => {
    this.showPrompt();
    this.scrollToBottom();
    this.resetInactivityTimer();
  }, 100);
};

Terminal.prototype.executeClickableCommand = function (command) {
  // Simulate typing the command like the initial help
  this.showCommand(command);
  this.inputLine.style.display = "none";

  // Execute the command after a short delay (skip the command display since we already did it)
  setTimeout(() => {
    // Handle special commands
    if (command === "clear") {
      this.clearTerminal();
      return;
    }

    // Handle projects subcommands
    if (command.startsWith("projects ")) {
      const parts = command.split(" ");
      if (parts.length === 2) {
        const subcommand = parts[1];
        this.loadProjectSubcommand(subcommand);
        return;
      }
    }

    // Load command from commands directory
    this.loadCommand(command);
  }, 500);
};
