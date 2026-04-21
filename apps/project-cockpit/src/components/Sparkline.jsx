/**
 * Sparkline — Canvas 2D inline metric visualization.
 *
 * Tufte-density: maximum data, minimum ink.
 * 48x16px default. Reactive to data changes via createEffect.
 *
 * Uses SolidJS reactivity properly — no polling, no setInterval.
 * Redraws only when props.data actually changes.
 */
import { onMount, createEffect } from "solid-js";

export default function Sparkline(props) {
  let canvasRef;
  const width = () => props.width || 48;
  const height = () => props.height || 16;

  function draw() {
    const data = props.data || [];
    if (!canvasRef || data.length < 2) return;

    const w = width();
    const h = height();
    const ctx = canvasRef.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    canvasRef.width = w * dpr;
    canvasRef.height = h * dpr;
    ctx.scale(dpr, dpr);

    ctx.clearRect(0, 0, w, h);

    const min = Math.min(...data);
    const max = Math.max(...data);
    const range = max - min || 1;
    const step = w / (data.length - 1);
    const pad = 1;

    // Color from design token (or explicit prop override)
    const color = props.color ||
      getComputedStyle(document.documentElement)
        .getPropertyValue("--truth-observed").trim() || "#51d6bd";

    // Line
    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.2;
    ctx.lineJoin = "round";

    for (let i = 0; i < data.length; i++) {
      const x = i * step;
      const y = pad + ((max - data[i]) / range) * (h - pad * 2);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // End dot (current value)
    const lastX = (data.length - 1) * step;
    const lastY = pad + ((max - data[data.length - 1]) / range) * (h - pad * 2);
    ctx.beginPath();
    ctx.arc(lastX, lastY, 1.5, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
  }

  onMount(() => draw());

  // Reactive redraw — SolidJS tracks props.data and calls draw when it changes
  createEffect(() => {
    // Access signals to establish dependency
    const _data = props.data;
    const _w = width();
    const _h = height();
    if (canvasRef) draw();
  });

  return (
    <canvas
      ref={canvasRef}
      width={width()}
      height={height()}
      style={{
        width: `${width()}px`,
        height: `${height()}px`,
        "vertical-align": "middle",
        "margin-left": "var(--space-2)",
        opacity: 0.85,
      }}
      aria-label={props.label || "Metric sparkline"}
      role="img"
    />
  );
}
