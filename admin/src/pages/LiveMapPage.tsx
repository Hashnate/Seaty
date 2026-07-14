import React, { useState, useEffect, useRef } from 'react';
import { Bus } from 'lucide-react';

// Simulated live bus data (same as original — will be replaced with real WebSocket data in production)
const MAP_VEHICLES = [
  {
    id: 'mv1', name: 'Highway Express 01', reg: 'WP-ND-8942',
    origin: 'Colombo', dest: 'Galle',
    route_coords: [
      { name: 'Colombo', x: 80, y: 150 }, { name: 'Kalutara', x: 85, y: 220 },
      { name: 'Ambalangoda', x: 92, y: 310 }, { name: 'Galle', x: 105, y: 370 }
    ],
    progress: 0.35, speed: 76, passengers: 28, heading: 165
  },
  {
    id: 'mv2', name: 'Kandy Intercity Luxury', reg: 'CP-NB-7721',
    origin: 'Colombo', dest: 'Kandy',
    route_coords: [
      { name: 'Colombo', x: 80, y: 150 }, { name: 'Kegalle', x: 160, y: 125 },
      { name: 'Kandy', x: 230, y: 110 }
    ],
    progress: 0.65, speed: 58, passengers: 32, heading: 45
  },
  {
    id: 'mv3', name: 'Yal Devi VIP Express', reg: 'NP-ND-2022',
    origin: 'Colombo', dest: 'Jaffna',
    route_coords: [
      { name: 'Colombo', x: 80, y: 150 }, { name: 'Kurunegala', x: 130, y: 100 },
      { name: 'Anuradhapura', x: 150, y: 50 }, { name: 'Jaffna', x: 120, y: -40 }
    ],
    progress: 0.15, speed: 82, passengers: 18, heading: 10
  }
];

export default function LiveMapPage() {
  const [liveBuses, setLiveBuses] = useState(MAP_VEHICLES);
  const [selectedBus, setSelectedBus] = useState<string | null>('mv1');
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  // Simulate movement
  useEffect(() => {
    const interval = setInterval(() => {
      setLiveBuses(prevBuses =>
        prevBuses.map(bus => {
          let nextProgress = bus.progress + 0.005;
          if (nextProgress > 1) nextProgress = 0;
          const segments = bus.route_coords.length - 1;
          const currentSegment = Math.min(Math.floor(nextProgress * segments), segments - 1);
          const p1 = bus.route_coords[currentSegment];
          const p2 = bus.route_coords[currentSegment + 1];
          const dx = p2.x - p1.x;
          const dy = p2.y - p1.y;
          const heading = Math.round((Math.atan2(dy, dx) * 180) / Math.PI) + 90;
          const speedOffset = Math.floor(Math.random() * 7) - 3;
          let nextSpeed = bus.speed + speedOffset;
          if (nextSpeed < 40) nextSpeed = 50;
          if (nextSpeed > 100) nextSpeed = 90;
          return { ...bus, progress: nextProgress, speed: nextSpeed, heading: heading >= 0 ? heading : heading + 360 };
        })
      );
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  // Canvas rendering
  useEffect(() => {
    if (!canvasRef.current) return;
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    let animId: number;
    const render = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      // Grid
      ctx.strokeStyle = 'rgba(230, 81, 0, 0.04)';
      ctx.lineWidth = 1;
      for (let x = 0; x < canvas.width; x += 40) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, canvas.height); ctx.stroke(); }
      for (let y = 0; y < canvas.height; y += 40) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(canvas.width, y); ctx.stroke(); }
      // Sri Lanka outline
      ctx.strokeStyle = 'rgba(10, 37, 64, 0.15)'; ctx.fillStyle = 'rgba(10, 37, 64, 0.02)'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(250, 40); ctx.bezierCurveTo(340, 100, 360, 240, 300, 380);
      ctx.bezierCurveTo(240, 480, 120, 460, 80, 380); ctx.bezierCurveTo(40, 300, 60, 200, 160, 80);
      ctx.closePath(); ctx.fill(); ctx.stroke();
      // Stations
      [{ name: 'Jaffna', x: 120, y: 50 }, { name: 'Anuradhapura', x: 170, y: 150 }, { name: 'Kandy', x: 240, y: 280 },
       { name: 'Colombo', x: 110, y: 320 }, { name: 'Galle', x: 130, y: 440 }].forEach(s => {
        ctx.shadowColor = '#e65100'; ctx.shadowBlur = 10; ctx.fillStyle = 'rgba(230, 81, 0, 0.8)';
        ctx.beginPath(); ctx.arc(s.x, s.y, 6, 0, Math.PI * 2); ctx.fill(); ctx.shadowBlur = 0;
        ctx.fillStyle = '#64748b'; ctx.font = '10px Inter'; ctx.fillText(s.name, s.x + 12, s.y + 4);
      });
      // Buses
      const getCoord = (c: { x: number; y: number }) => ({ x: c.x + 60, y: c.y + 160 });
      liveBuses.forEach(bus => {
        ctx.strokeStyle = 'rgba(10, 37, 64, 0.15)'; ctx.lineWidth = 3; ctx.beginPath();
        const start = getCoord(bus.route_coords[0]); ctx.moveTo(start.x, start.y);
        for (let i = 1; i < bus.route_coords.length; i++) { const n = getCoord(bus.route_coords[i]); ctx.lineTo(n.x, n.y); }
        ctx.stroke();
        const segs = bus.route_coords.length - 1;
        const seg = Math.min(Math.floor(bus.progress * segs), segs - 1);
        const segP = (bus.progress * segs) - seg;
        const p1 = getCoord(bus.route_coords[seg]); const p2 = getCoord(bus.route_coords[seg + 1]);
        const cx = p1.x + (p2.x - p1.x) * segP; const cy = p1.y + (p2.y - p1.y) * segP;
        const isSel = bus.id === selectedBus;
        if (isSel) { ctx.strokeStyle = '#e65100'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(cx, cy, 15 + Math.sin(Date.now() / 150) * 3, 0, Math.PI * 2); ctx.stroke(); }
        ctx.fillStyle = isSel ? '#e65100' : '#1e3a8a'; ctx.beginPath(); ctx.arc(cx, cy, 7, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#0a2540'; ctx.font = 'bold 9px Inter'; ctx.fillText(bus.reg, cx - 22, cy - 12);
      });
      animId = requestAnimationFrame(render);
    };
    render();
    return () => cancelAnimationFrame(animId);
  }, [liveBuses, selectedBus]);

  const selBus = liveBuses.find(b => b.id === selectedBus);

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Real-Time Fleet Radar</h1>
          <p className="page-subtitle">Live tracking of luxury vehicles commuting in Sri Lanka via WebSocket GPS feeds.</p>
        </div>
      </div>
      <div className="map-canvas-container">
        <div className="map-sidebar">
          <h3 className="map-sidebar-title">Active Transporters ({liveBuses.length})</h3>
          <div className="map-bus-list">
            {liveBuses.map(bus => (
              <div key={bus.id} className={`map-bus-item ${selectedBus === bus.id ? 'selected' : ''}`} onClick={() => setSelectedBus(bus.id)}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                  <span style={{ fontSize: '13px', fontWeight: 'bold' }}>{bus.name}</span>
                  <span className="badge badge-success" style={{ fontSize: '9px', padding: '2px 5px' }}>Active</span>
                </div>
                <div style={{ fontSize: '11px', color: '#9ca3af', display: 'flex', justifyContent: 'space-between' }}>
                  <span>Plate: {bus.reg}</span><span>Speed: {bus.speed} km/h</span>
                </div>
                <div style={{ fontSize: '11px', color: '#9ca3af', marginTop: '4px' }}>
                  Route: {bus.origin} &rarr; {bus.dest}
                </div>
              </div>
            ))}
          </div>
        </div>
        <div className="map-canvas-element">
          <canvas ref={canvasRef} width={500} height={480} style={{ display: 'block', width: '100%', height: '100%' }} />
          {selBus && (
            <div className="map-stats-overlay">
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px', borderBottom: '1px solid var(--border-color)', paddingBottom: '6px' }}>
                <Bus size={18} style={{ color: '#e65100' }} />
                <strong style={{ fontSize: '14px' }}>{selBus.name} ({selBus.reg})</strong>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px 16px', fontSize: '12px' }}>
                <div>Status: <span style={{ color: '#10b981', fontWeight: 'bold' }}>ON-ROUTE</span></div>
                <div>Speed: <span style={{ fontWeight: 'bold' }}>{selBus.speed} km/h</span></div>
                <div>Load: <span style={{ fontWeight: 'bold' }}>{selBus.passengers} pax</span></div>
                <div>Bearing: <span style={{ fontWeight: 'bold' }}>{selBus.heading}&deg;</span></div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
