(() => {
  "use strict";
  const canvas = document.querySelector("#atmosphere");
  const context = canvas.getContext("2d");
  const eye = document.querySelector(".eye-link");
  const iris = document.querySelector(".iris");
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  if (!context) return; // The download remains a normal, usable link without Canvas.

  let width = 0;
  let height = 0;
  let center = { x: 0, y: 0, radius: 0 };
  let trails = [];
  let frame = 0;
  let last = 0;
  let time = 0;
  let hover = false;
  const pointer = { x: 0, y: 0, targetX: 0, targetY: 0, vx: 0, vy: 0, active: false };
  const tau = Math.PI * 2;

  function locateEye() {
    const rect = eye.getBoundingClientRect();
    center = { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2, radius: rect.width * 0.43 };
  }

  function seedTrail(index) {
    const x = Math.random() * width;
    const y = Math.random() * height;
    return { x, y, phase: index * 2.39996, age: 0, points: new Float32Array(64), cursor: 0 };
  }

  function resize() {
    width = innerWidth;
    height = innerHeight;
    const scale = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    context.setTransform(scale, 0, 0, scale, 0, 0);
    locateEye();
    trails = Array.from({ length: Math.min(110, Math.max(40, Math.round(width * height / 12000))) }, (_, i) => seedTrail(i));
    if (!pointer.active) {
      pointer.x = pointer.targetX = width / 2;
      pointer.y = pointer.targetY = height / 2;
    }
    if (motion.matches) draw(false);
  }

  function drawWind(moving) {
    for (const trail of trails) {
      if (moving) {
        const dx = trail.x - pointer.x;
        const dy = trail.y - pointer.y;
        const influence = pointer.active ? Math.exp(-(dx * dx + dy * dy) / 110000) : 0;
        const angle = Math.sin(trail.y * 0.003 + time * 0.12) * 1.2 + Math.cos(trail.x * 0.002 + trail.phase) * 0.5;
        trail.x += Math.cos(angle) * 0.9 - dy * influence * 0.012 + pointer.vx * influence * 0.45;
        trail.y += Math.sin(angle) * 0.8 + dx * influence * 0.012 + pointer.vy * influence * 0.45;
        if (trail.x < -30 || trail.x > width + 30 || trail.y < -30 || trail.y > height + 30) {
          trail.x = Math.random() * width;
          trail.y = Math.random() * height;
          trail.age = 0;
        }
        trail.points[trail.cursor * 2] = trail.x;
        trail.points[trail.cursor * 2 + 1] = trail.y;
        trail.cursor = (trail.cursor + 1) % 32;
        trail.age = Math.min(trail.age + 1, 32);
      }
      const intensity = 0.09 + (Math.sin(trail.phase) + 1) * 0.08;
      context.strokeStyle = `rgba(178,157,229,${intensity})`;
      context.lineWidth = 0.65;
      context.beginPath();
      if (moving && trail.age > 1) {
        for (let i = 0; i < trail.age; i++) {
          const index = ((trail.cursor - trail.age + i + 32) % 32) * 2;
          if (i === 0) context.moveTo(trail.points[index], trail.points[index + 1]);
          else context.lineTo(trail.points[index], trail.points[index + 1]);
        }
      } else {
        context.moveTo(trail.x, trail.y);
        context.quadraticCurveTo(trail.x + 10, trail.y - 5, trail.x + 22, trail.y - 3);
      }
      context.stroke();
    }
  }

  function draw(moving) {
    context.clearRect(0, 0, width, height);
    drawWind(moving);
    const { x, y, radius } = center;
    const glow = context.createRadialGradient(x, y, 8, x, y, radius * 2.1);
    glow.addColorStop(0, "rgba(136,99,219,0.11)");
    glow.addColorStop(0.5, "rgba(112,78,198,0.035)");
    glow.addColorStop(1, "rgba(112,78,198,0)");
    context.fillStyle = glow;
    context.fillRect(x - radius * 2.1, y - radius * 2.1, radius * 4.2, radius * 4.2);
    for (let lane = 0; lane < 3; lane++) {
      const tilt = -0.45 + lane * 0.43;
      const a = radius * (1 + lane * 0.09);
      const b = radius * (0.64 + lane * 0.07);
      context.beginPath();
      context.ellipse(x, y, a, b, tilt, 0, tau);
      context.strokeStyle = `rgba(190,167,240,${hover ? 0.14 : 0.07})`;
      context.lineWidth = 0.6;
      context.stroke();
      for (let i = 0; i < 15; i++) {
        const angle = i * tau / 15 + time * (0.12 + lane * 0.035) + lane * 1.7;
        const u = Math.cos(angle) * a;
        const v = Math.sin(angle) * b;
        const px = x + u * Math.cos(tilt) - v * Math.sin(tilt);
        const py = y + u * Math.sin(tilt) + v * Math.cos(tilt);
        const alpha = 0.23 + (Math.sin(angle + lane) + 1) * 0.25;
        const size = i % 4 === 0 ? 1.55 : 0.85;
        context.beginPath();
        context.arc(px, py, size * 4.5, 0, tau);
        const bloom = context.createRadialGradient(px, py, 0, px, py, size * 4.5);
        bloom.addColorStop(0, `rgba(190,167,255,${alpha * 0.4})`);
        bloom.addColorStop(1, "rgba(190,167,255,0)");
        context.fillStyle = bloom;
        context.fill();
        context.beginPath();
        context.arc(px, py, size, 0, tau);
        context.fillStyle = `rgba(${i % 3 === 0 ? "171,209,242" : "223,209,255"},${alpha})`;
        context.fill();
      }
    }
  }

  function tick(now) {
    if (document.hidden || motion.matches) { frame = 0; return; }
    frame = requestAnimationFrame(tick);
    if (now - last < 32) return;
    time += Math.min((now - last) / 1000, 0.05);
    last = now;
    pointer.vx = (pointer.targetX - pointer.x) * 0.1;
    pointer.vy = (pointer.targetY - pointer.y) * 0.1;
    pointer.x += pointer.vx;
    pointer.y += pointer.vy;
    const dx = pointer.active ? (pointer.x - center.x) / Math.max(width, 1) * 13 : 0;
    const dy = pointer.active ? (pointer.y - center.y) / Math.max(height, 1) * 10 : 0;
    iris.setAttribute("transform", `translate(${dx.toFixed(2)} ${dy.toFixed(2)})`);
    draw(true);
  }

  function syncMotion() {
    cancelAnimationFrame(frame);
    frame = 0;
    last = performance.now();
    if (motion.matches) {
      time = 0;
      iris.removeAttribute("transform");
      draw(false);
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
  window.addEventListener("scroll", () => { locateEye(); if (motion.matches) draw(false); }, { passive: true });
  eye.addEventListener("pointerenter", () => { hover = true; });
  eye.addEventListener("pointerleave", () => { hover = false; });
  eye.addEventListener("click", () => {
    if (!motion.matches) document.querySelector(".eye").animate(
      [{ transform: "scaleY(1)" }, { transform: "scaleY(.09)" }, { transform: "scaleY(1)" }],
      { duration: 320, easing: "ease-in-out" });
  });
  motion.addEventListener("change", syncMotion);
  document.addEventListener("visibilitychange", syncMotion);
  resize();
  syncMotion();
})();
