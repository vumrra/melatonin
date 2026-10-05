(() => {
  "use strict";
  const canvas = document.querySelector("#atmosphere");
  const context = canvas.getContext("2d");
  const eye = document.querySelector(".eye-link");
  const iris = document.querySelector(".iris");
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  if (!context) return;

  let width = 0;
  let height = 0;
  let frame = 0;
  let last = 0;
  let time = 0;
  const pointer = { x: 0, y: 0, targetX: 0, targetY: 0, strength: 0, active: false };

  function draw() {
    context.clearRect(0, 0, width, height);
    const scale = Math.max(width, height);
    const originX = width * 0.75;
    const originY = height * 0.48;
    for (let band = 0; band < 19; band++) {
      const radius = scale * (0.06 + band * 0.044);
      context.beginPath();
      for (let step = 0; step <= 160; step++) {
        const angle = step / 160 * Math.PI * 2;
        const ripple = Math.sin(angle * 3 + band * 0.11 + time * 0.14) * 0.13
          + Math.cos(angle * 5 - time * 0.09) * 0.045;
        let x = originX + Math.cos(angle) * radius * (1 + ripple);
        let y = originY + Math.sin(angle) * radius * (0.85 + ripple);
        x += Math.sin(y / scale * 8 + time * 0.09) * scale * 0.075;
        y += Math.sin(x / scale * 6 - time * 0.11) * scale * 0.045;
        const dx = x - pointer.x;
        const dy = y - pointer.y;
        const influence = Math.exp(-(dx * dx + dy * dy) / (scale * scale * 0.055)) * pointer.strength;
        x += (dx * 0.19 - dy * 0.16) * influence;
        y += (dy * 0.19 + dx * 0.16) * influence;
        if (step === 0) context.moveTo(x, y);
        else context.lineTo(x, y);
      }
      context.closePath();
      const light = 0.10 + (Math.sin(band * 0.63 + time * 0.12) + 1) * 0.035;
      context.strokeStyle = `rgba(132,109,211,${light * 0.16})`;
      context.lineWidth = 10;
      context.stroke();
      context.strokeStyle = `rgba(155,131,226,${light * 0.3})`;
      context.lineWidth = 4;
      context.stroke();
      context.strokeStyle = `rgba(172,147,239,${light})`;
      context.lineWidth = 1.1;
      context.stroke();
    }
    // Keep the eye and typography quiet while contour bands fill the edges.
    const veil = context.createRadialGradient(width / 2, height / 2, 0, width / 2, height / 2, scale * 0.46);
    veil.addColorStop(0, "rgba(8,7,16,0.88)");
    veil.addColorStop(0.42, "rgba(8,7,16,0.65)");
    veil.addColorStop(1, "rgba(8,7,16,0)");
    context.fillStyle = veil;
    context.fillRect(0, 0, width, height);
  }

  function resize() {
    width = innerWidth;
    height = innerHeight;
    const scale = Math.min(devicePixelRatio || 1, 1.5);
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.lineJoin = "round";
    if (!pointer.active) {
      pointer.x = pointer.targetX = width * 0.75;
      pointer.y = pointer.targetY = height * 0.48;
    }
    draw();
  }

  function tick(now) {
    if (document.hidden || motion.matches) { frame = 0; return; }
    frame = requestAnimationFrame(tick);
    if (now - last < 32) return;
    time += Math.min((now - last) / 1000, 0.05);
    last = now;
    pointer.x += (pointer.targetX - pointer.x) * 0.08;
    pointer.y += (pointer.targetY - pointer.y) * 0.08;
    pointer.strength += ((pointer.active ? 1 : 0) - pointer.strength) * 0.06;
    const bounds = eye.getBoundingClientRect();
    const dx = pointer.active ? (pointer.x - bounds.left - bounds.width / 2) / width * 13 : 0;
    const dy = pointer.active ? (pointer.y - bounds.top - bounds.height / 2) / height * 10 : 0;
    iris.setAttribute("transform", `translate(${dx.toFixed(2)} ${dy.toFixed(2)})`);
    draw();
  }

  function syncMotion() {
    cancelAnimationFrame(frame);
    frame = 0;
    last = performance.now();
    if (motion.matches) {
      time = 0;
      pointer.strength = 0;
      iris.removeAttribute("transform");
      draw();
    } else if (!document.hidden) frame = requestAnimationFrame(tick);
  }

  window.addEventListener("pointermove", event => {
    pointer.targetX = event.clientX;
    pointer.targetY = event.clientY;
    pointer.active = true;
  }, { passive: true });
  document.addEventListener("pointerleave", () => { pointer.active = false; });
  window.addEventListener("blur", () => { pointer.active = false; });
  window.addEventListener("resize", resize, { passive: true });
  motion.addEventListener("change", syncMotion);
  document.addEventListener("visibilitychange", syncMotion);
  resize();
  syncMotion();
})();
