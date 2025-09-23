window.addEventListener("load", () => {
  // Additional delay to ensure all CSS is applied
  setTimeout(() => {
    const shardContainers = document.querySelectorAll(".shard");

    shardContainers.forEach((shardContainer) => {
      const images = shardContainer.querySelectorAll("img");

      // Get dimensions from data attributes
      const charsPerLine = parseInt(shardContainer.dataset.width) || 50;
      const numRows = parseInt(shardContainer.dataset.height) || 25;

      // Default image is the first one, artifacts are the rest
      const defaultImage = images[0];
      const artifactImages = Array.from(images).slice(1);

      // Create shards container
      const shardsWrapper = document.createElement("div");
      shardsWrapper.className = "image-shards";
      shardContainer.appendChild(shardsWrapper);

      // Hide original images
      images.forEach((img) => (img.style.display = "none"));

      function getRandomInt(min, max) {
        return Math.floor(Math.random() * (max - min + 1)) + min;
      }

      function createImageShard(vertices, imageUrl) {
        const shard = document.createElement("div");
        shard.className = "image-shard";

        // Calculate bounding box
        const minX = Math.min(...vertices.map((v) => v.x));
        const maxX = Math.max(...vertices.map((v) => v.x));
        const minY = Math.min(...vertices.map((v) => v.y));
        const maxY = Math.max(...vertices.map((v) => v.y));

        // Coordinates are already in percentage (0-100)
        const left = minX;
        const top = minY;
        const width = maxX - minX;
        const height = maxY - minY;

        shard.style.left = `${left}%`;
        shard.style.top = `${top}%`;
        shard.style.width = `${width}%`;
        shard.style.height = `${height}%`;

        // Create polygon clip path relative to shard bounds
        const clipVertices = vertices
          .map(
            (v) =>
              `${((v.x - minX) / (maxX - minX)) * 100}% ${((v.y - minY) / (maxY - minY)) * 100}%`,
          )
          .join(", ");
        shard.style.clipPath = `polygon(${clipVertices})`;

        // Calculate background size and position relative to parent container
        // Background size needs to be scaled up so the full image appears across all shards
        const bgWidth = (100 / width) * 100; // Scale to show full width across parent
        const bgHeight = (100 / height) * 100; // Scale to show full height across parent

        // Position offset to show correct portion
        const bgX = -(left / width) * 100;
        const bgY = -(top / height) * 100;

        shard.style.backgroundImage = `url(${imageUrl})`;
        shard.style.backgroundPosition = `${bgX < 0 ? bgX + bgWidth : bgX}% ${bgY < 0 ? bgY + bgHeight : bgY}%`;
        shard.style.backgroundSize = `${bgWidth}% ${bgHeight}%`;
        shard.style.backgroundRepeat = "repeat";

        return shard;
      }

      function generateTriangularShards() {
        const shards = [];

        // Center point of the container (50%, 50%)
        const centerX = getRandomInt(30, 70);
        const centerY = getRandomInt(30, 70);

        // Generate random points on each edge (30-70% along each edge)
        const topEdgeX = getRandomInt(30, 70);
        const rightEdgeY = getRandomInt(30, 70);
        const bottomEdgeX = getRandomInt(30, 70);
        const leftEdgeY = getRandomInt(30, 70);

        // Define corners (0-100% coordinates)
        const topLeft = { x: 0, y: 0 };
        const topRight = { x: 100, y: 0 };
        const bottomRight = { x: 100, y: 100 };
        const bottomLeft = { x: 0, y: 100 };

        // Define edge points
        const topEdge = { x: topEdgeX, y: 0 };
        const rightEdge = { x: 100, y: rightEdgeY };
        const bottomEdge = { x: bottomEdgeX, y: 100 };
        const leftEdge = { x: 0, y: leftEdgeY };

        const center = { x: centerX, y: centerY };

        // Create 8 triangular shards: corner -> edge -> center
        shards.push([topLeft, topEdge, center]);
        shards.push([topEdge, topRight, center]);
        shards.push([topRight, rightEdge, center]);
        shards.push([rightEdge, bottomRight, center]);
        shards.push([bottomRight, bottomEdge, center]);
        shards.push([bottomEdge, bottomLeft, center]);
        shards.push([bottomLeft, leftEdge, center]);
        shards.push([leftEdge, topLeft, center]);

        return shards;
      }

      // Generate base shards once on load
      const baseShards = generateTriangularShards();

      // Create base image display using default image
      function initializeShards() {
        shardsWrapper.innerHTML = "";
        baseShards.forEach((vertices) => {
          const shard = createImageShard(vertices, defaultImage.src);
          shard.classList.add("base-shard");
          shardsWrapper.appendChild(shard);
        });
      }

      function flickerShards() {
        if (artifactImages.length === 0) return;

        // Randomly select some shards to flicker
        const numToFlicker = getRandomInt(1, Math.min(3, baseShards.length));
        const shardsToFlicker = [];

        for (let i = 0; i < numToFlicker; i++) {
          const randomIndex = getRandomInt(0, baseShards.length - 1);
          if (!shardsToFlicker.includes(randomIndex)) {
            shardsToFlicker.push(randomIndex);
          }
        }

        shardsToFlicker.forEach((shardIndex) => {
          // Pick a random artifact image
          const artifactImage =
            artifactImages[getRandomInt(0, artifactImages.length - 1)];
          const flickerShard = createImageShard(
            baseShards[shardIndex],
            artifactImage.src,
          );
          flickerShard.classList.add("flicker-shard");
          flickerShard.style.zIndex = "10";
          shardsWrapper.appendChild(flickerShard);
        });

        // Remove flicker shards after a short time
        setTimeout(
          () => {
            const flickerShards =
              shardsWrapper.querySelectorAll(".flicker-shard");
            flickerShards.forEach((shard) => shard.remove());
          },
          getRandomInt(100, 300),
        );
      }

      function startFlickering() {
        setTimeout(flickerShards, getRandomInt(100, 300));
        setTimeout(flickerShards, getRandomInt(200, 500));
        setTimeout(flickerShards, getRandomInt(300, 700));
        setTimeout(startFlickering, getRandomInt(1500, 3000));
      }

      // Initialize the shards and start flickering
      initializeShards();
      if (artifactImages.length > 0) {
        startFlickering();
      }
    });
  }, 1000);
});
