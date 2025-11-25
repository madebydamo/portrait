// Tab completion methods for Terminal class

Terminal.prototype.handleTabCompletion = async function () {
  const currentInput = this.input.value;
  const cursorPosition = this.input.selectionStart;

  // Get the current word being typed (from cursor back to last space or start)
  const beforeCursor = currentInput.substring(0, cursorPosition);
  const lastSpaceIndex = beforeCursor.lastIndexOf(" ");
  const currentWord =
    lastSpaceIndex === -1
      ? beforeCursor
      : beforeCursor.substring(lastSpaceIndex + 1);

  if (!currentWord) return;

  try {
    // Determine completion type based on position
    const isFirstWord = lastSpaceIndex === -1;
    let completionCommand;

    if (isFirstWord) {
      // Complete commands
      completionCommand = `compgen -c "${currentWord}"`;
    } else {
      // Complete files/directories
      const prefix = beforeCursor.substring(0, lastSpaceIndex + 1);
      completionCommand = `compgen -f "${currentWord}"`;
    }

    const response = await fetch("/execute", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ command: completionCommand }),
    });

      if (response.ok) {
        const data = await response.json();
        // Filter out duplicates and empty lines
        let completions = [
          ...new Set(
            data.stdout
              .trim()
              .split("\n")
              .map((line) => line.trim())
              .filter((line) => line),
          ),
        ];

      // For first word completion, add custom portfolio commands that match
      if (isFirstWord && this.availableCommands) {
        const matchingCustomCommands = this.availableCommands.filter(
          (cmd) => cmd.startsWith(currentWord) && !completions.includes(cmd),
        );
        completions = [...new Set([...completions, ...matchingCustomCommands])];
      }

      if (completions.length === 0) {
        // No completions found
        return;
      }

      if (completions.length === 1) {
        // Single completion - auto-complete
        const completion = completions[0];
        if (isFirstWord) {
          this.input.value = completion + " ";
        } else {
          const prefix = beforeCursor.substring(0, lastSpaceIndex + 1);
          this.input.value = prefix + completion + " ";
        }
        // Reset cursor to end
        this.input.setSelectionRange(
          this.input.value.length,
          this.input.value.length,
        );
      } else {
        // Multiple completions - show options
        this.clearCompletionOptions();
        const maxCompletions = 10;
        let displayCompletions = completions.slice(0, maxCompletions);
        let overflowMessage = "";

        if (completions.length > maxCompletions) {
          displayCompletions = completions.slice(0, maxCompletions);
          overflowMessage = `... and ${completions.length - maxCompletions} more`;
        }

        // Show completions below the prompt
        const completionDiv = document.createElement("div");
        completionDiv.innerHTML = `<div>${displayCompletions.join("  ")}${overflowMessage ? "  " + overflowMessage : ""}</div>`;
        this.completionContainer.appendChild(completionDiv);

        // Find common prefix for partial completion
        if (displayCompletions.length > 1) {
          const commonPrefix = this.findCommonPrefix(displayCompletions);
          if (commonPrefix.length > currentWord.length) {
            // Partial completion possible
            if (isFirstWord) {
              this.input.value = commonPrefix;
            } else {
              const prefix = beforeCursor.substring(0, lastSpaceIndex + 1);
              this.input.value = prefix + commonPrefix;
            }
            // Set cursor to end of completed part
            this.input.setSelectionRange(
              this.input.value.length,
              this.input.value.length,
            );
          }
        }
      }
    }
  } catch (error) {
    console.error("Tab completion error:", error);
  }
};

Terminal.prototype.findCommonPrefix = function (strings) {
  if (strings.length === 0) return "";
  if (strings.length === 1) return strings[0];

  let prefix = strings[0];
  for (let i = 1; i < strings.length; i++) {
    while (strings[i].indexOf(prefix) !== 0) {
      prefix = prefix.substring(0, prefix.length - 1);
      if (prefix === "") return "";
    }
  }
  return prefix;
};

Terminal.prototype.clearCompletionOptions = function () {
  this.completionContainer.innerHTML = "";
};
