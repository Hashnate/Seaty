import { useState, useEffect, useRef } from 'react';
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
      ctx.strokeStyle = 'rgba(10, 37, 64, 0.03)';
      ctx.lineWidth = 1;
      for (let x = 0; x < canvas.width; x += 40) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, canvas.height); ctx.stroke(); }
      for (let y = 0; y < canvas.height; y += 40) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(canvas.width, y); ctx.stroke(); }
      // Sri Lanka outline
      ctx.strokeStyle = 'rgba(10, 37, 64, 0.08)'; ctx.fillStyle = 'rgba(10, 37, 64, 0.005)'; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(250, 40); ctx.bezierCurveTo(340, 100, 360, 240, 300, 380);
      ctx.bezierCurveTo(240, 480, 120, 460, 80, 380); ctx.bezierCurveTo(40, 300, 60, 200, 160, 80);
      ctx.closePath(); ctx.fill(); ctx.stroke();
      // Stations
      [{ name: 'Jaffna', x: 120, y: 50 }, { name: 'Anuradhapura', x: 170, y: 150 }, { name: 'Kandy', x: 240, y: 280 },
       { name: 'Colombo', x: 110, y: 320 }, { name: 'Galle', x: 130, y: 440 }].forEach(s => {
        ctx.shadowColor = 'rgba(37, 99, 235, 0.3)'; ctx.shadowBlur = 8; ctx.fillStyle = 'rgba(37, 99, 235, 0.9)';
        ctx.beginPath(); ctx.arc(s.x, s.y, 5, 0, Math.PI * 2); ctx.fill(); 
        ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 1; ctx.stroke(); ctx.shadowBlur = 0;
        ctx.fillStyle = '#64748b'; ctx.font = '500 10px Inter'; ctx.fillText(s.name, s.x + 12, s.y + 4);
      });
      // Buses
      const getCoord = (c: { x: number; y: number }) => ({ x: c.x + 60, y: c.y + 160 });
      liveBuses.forEach(bus => {
        ctx.strokeStyle = 'rgba(10, 37, 64, 0.08)'; ctx.lineWidth = 2; ctx.beginPath();
        const start = getCoord(bus.route_coords[0]); ctx.moveTo(start.x, start.y);
        for (let i = 1; i < bus.route_coords.length; i++) { const n = getCoord(bus.route_coords[i]); ctx.lineTo(n.x, n.y); }
        ctx.stroke();
        const segs = bus.route_coords.length - 1;
        const seg = Math.min(Math.floor(bus.progress * segs), segs - 1);
        const segP = (bus.progress * segs) - seg;
        const p1 = getCoord(bus.route_coords[seg]); const p2 = getCoord(bus.route_coords[seg + 1]);
        const cx = p1.x + (p2.x - p1.x) * segP; const cy = p1.y + (p2.y - p1.y) * segP;
        const isSel = bus.id === selectedBus;
        if (isSel) { ctx.strokeStyle = 'var(--color-primary)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(cx, cy, 12 + Math.sin(Date.now() / 150) * 2, 0, Math.PI * 2); ctx.stroke(); }
        ctx.fillStyle = isSel ? 'var(--color-primary)' : 'var(--color-secondary)'; ctx.beginPath(); ctx.arc(cx, cy, 6, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 1.5; ctx.stroke();
        ctx.fillStyle = 'var(--text-dark)'; ctx.font = '700 9px Inter'; 
        ctx.shadowColor = '#ffffff'; ctx.shadowBlur = 3;
        ctx.fillText(bus.reg, cx - 22, cy - 12); ctx.shadowBlur = 0;
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
              <div key={bus.id} className={`map-bus-item ${selectedBus === bus.id ? 'selected' : ''}`} onClick={() => setSelectedBus(bus.id)} style={{ padding: '16px' }}>
                {/* Header */}
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '12px', alignItems: 'center' }}>
                  <span style={{ fontSize: '13.5px', fontWeight: 700, color: 'var(--text-dark)' }}>{bus.name}</span>
                  <span style={{ 
                    display: 'inline-flex', 
                    alignItems: 'center', 
                    fontSize: '10px', 
                    fontWeight: 700, 
                    color: '#10b981', 
                    background: 'rgba(16, 185, 129, 0.08)', 
                    padding: '2px 8px', 
                    borderRadius: '12px',
                    border: '1px solid rgba(16, 185, 129, 0.15)'
                  }}>
                    <span className="live-status-dot" style={{ width: '5px', height: '5px', marginRight: '4px' }} />
                    Active
                  </span>
                </div>
                
                {/* Route */}
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginBottom: '12px', background: 'var(--bg-secondary)', padding: '6px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', fontWeight: 600 }}>
                  {bus.origin} &rarr; {bus.dest}
                </div>
                
                {/* Details Grid */}
                <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '8px', borderTop: '1px solid rgba(0,0,0,0.03)', paddingTop: '10px' }}>
                  <div>
                    <div style={{ fontSize: '9px', textTransform: 'uppercase', letterSpacing: '0.04em', color: 'var(--text-muted)', fontWeight: 600 }}>Plate Number</div>
                    <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-dark)', marginTop: '2px' }}>{bus.reg}</div>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <div style={{ fontSize: '9px', textTransform: 'uppercase', letterSpacing: '0.04em', color: 'var(--text-muted)', fontWeight: 600 }}>Live Speed</div>
                    <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--color-primary)', marginTop: '2px' }}>{bus.speed} km/h</div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div className="map-canvas-element">
          <canvas ref={canvasRef} width={500} height={480} style={{ display: 'block', width: '100%', height: '100%' }} />
          {selBus && (
            <div className="map-stats-overlay">
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '10px', borderBottom: '1px solid var(--border-color)', paddingBottom: '8px' }}>
                <Bus size={16} style={{ color: 'var(--color-primary)' }} />
                <strong style={{ fontSize: '13.5px', color: 'var(--text-dark)', fontWeight: 700 }}>{selBus.name}</strong>
                <span style={{ fontSize: '10px', color: 'var(--text-muted)', background: 'var(--bg-secondary)', padding: '2px 6px', borderRadius: '4px', border: '1px solid var(--border-color)', fontWeight: 600 }}>{selBus.reg}</span>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px 16px', fontSize: '11.5px', fontWeight: 500 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Status:</span>
                  <span style={{ 
                    display: 'inline-flex', 
                    alignItems: 'center', 
                    color: '#10b981', 
                    fontWeight: 700 
                  }}>
                    <span className="live-status-dot" style={{ width: '5px', height: '5px', marginRight: '4px' }} />
                    ON-ROUTE
                  </span>
                </div>
                <div><span style={{ color: 'var(--text-muted)' }}>Speed:</span> <span style={{ fontWeight: 700, color: 'var(--text-dark)' }}>{selBus.speed} km/h</span></div>
                <div><span style={{ color: 'var(--text-muted)' }}>Load:</span> <span style={{ fontWeight: 700, color: 'var(--text-dark)' }}>{selBus.passengers} pax</span></div>
                <div><span style={{ color: 'var(--text-muted)' }}>Bearing:</span> <span style={{ fontWeight: 700, color: 'var(--text-dark)' }}>{selBus.heading}&deg;</span></div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
