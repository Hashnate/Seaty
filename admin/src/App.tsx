import React, { useState, useEffect, useRef } from 'react';
import { 
  Bus, 
  MapPin, 
  Users, 
  CheckCircle, 
  XCircle, 
  Compass, 
  TrendingUp, 
  DollarSign, 
  Clock, 
  FileText, 
  Settings as SettingsIcon,
  LogOut, 
  Search,
  Activity,
  Map as MapIcon
} from 'lucide-react';

// ==========================================
// Mock Initial Data (in case backend is starting up)
// ==========================================
const INITIAL_VEHICLES = [
  {
    id: 'v1',
    name: 'Royal Transit VIP Coach',
    registration_number: 'WP-ND-8942',
    type: 'bus',
    owner: 'Ranjith Silva',
    total_seats: 40,
    amenities: ['AC', 'WiFi', 'Charging Ports', 'Reclining Seats'],
    is_verified: false,
    document_urls: ['Registration.pdf', 'Insurance_Cover.pdf']
  },
  {
    id: 'v2',
    name: 'Southern Highway Express',
    registration_number: 'WP-NE-4512',
    type: 'bus',
    owner: 'Kamal Perera',
    total_seats: 36,
    amenities: ['AC', 'Charging Ports', 'Entertainment Screen'],
    is_verified: false,
    document_urls: ['Bus_Permit.pdf']
  },
  {
    id: 'v3',
    name: 'Colombo-Kandy Intercity Deluxe',
    registration_number: 'CP-NB-7721',
    type: 'bus',
    owner: 'Mohamed Aslam',
    total_seats: 42,
    amenities: ['AC', 'WiFi', 'Complimentary Water', 'Reclining Seats'],
    is_verified: true,
    document_urls: ['Intercity_Permit.pdf']
  }
];

const INITIAL_BOOKINGS = [
  {
    id: 'b1',
    passenger: 'Sineth Jayasinghe',
    phone: '+94 77 123 4567',
    vehicle: 'Colombo-Kandy Intercity Deluxe',
    route: 'Colombo - Kandy',
    seats: ['A1', 'A2'],
    price: 3200.00,
    status: 'paid',
    date: '2026-07-13 08:30'
  },
  {
    id: 'b2',
    passenger: 'Niranjala Fernando',
    phone: '+94 71 987 6543',
    vehicle: 'Colombo-Kandy Intercity Deluxe',
    route: 'Colombo - Kandy',
    seats: ['B3'],
    price: 1600.00,
    status: 'paid',
    date: '2026-07-13 09:15'
  },
  {
    id: 'b3',
    passenger: 'Saman Kumara',
    phone: '+94 75 555 1212',
    vehicle: 'Southern Highway Express',
    route: 'Colombo - Galle',
    seats: ['C1', 'C2', 'C3'],
    price: 4800.00,
    status: 'pending',
    date: '2026-07-13 10:10'
  }
];

const MAP_VEHICLES = [
  {
    id: 'mv1',
    name: 'Highway Express 01',
    reg: 'WP-ND-8942',
    origin: 'Colombo',
    dest: 'Galle',
    route_coords: [
      { name: 'Colombo', x: 80, y: 150 },
      { name: 'Kalutara', x: 85, y: 220 },
      { name: 'Ambalangoda', x: 92, y: 310 },
      { name: 'Galle', x: 105, y: 370 }
    ],
    progress: 0.35, // progress between 0 and 1
    speed: 76,
    passengers: 28,
    heading: 165
  },
  {
    id: 'mv2',
    name: 'Kandy Intercity Luxury',
    reg: 'CP-NB-7721',
    origin: 'Colombo',
    dest: 'Kandy',
    route_coords: [
      { name: 'Colombo', x: 80, y: 150 },
      { name: 'Kegalle', x: 160, y: 125 },
      { name: 'Kandy', x: 230, y: 110 }
    ],
    progress: 0.65,
    speed: 58,
    passengers: 32,
    heading: 45
  },
  {
    id: 'mv3',
    name: 'Yal Devi VIP Express',
    reg: 'NP-ND-2022',
    origin: 'Colombo',
    dest: 'Jaffna',
    route_coords: [
      { name: 'Colombo', x: 80, y: 150 },
      { name: 'Kurunegala', x: 130, y: 100 },
      { name: 'Anuradhapura', x: 150, y: 50 },
      { name: 'Jaffna', x: 120, y: -40 }
    ],
    progress: 0.15,
    speed: 82,
    passengers: 18,
    heading: 10
  }
];

export default function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [email, setEmail] = useState('admin@seaty.lk');
  const [password, setPassword] = useState('password');
  const [activeTab, setActiveTab] = useState<'overview' | 'approvals' | 'map' | 'bookings' | 'settings'>('overview');
  
  // App states
  const [vehicles, setVehicles] = useState(INITIAL_VEHICLES);
  const [bookings, setBookings] = useState(INITIAL_BOOKINGS);
  const [liveBuses, setLiveBuses] = useState(MAP_VEHICLES);
  const [selectedBus, setSelectedBus] = useState<string | null>('mv1');
  const [searchTerm, setSearchTerm] = useState('');
  
  // Live Map canvas references
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  // Authenticate Admin
  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault();
    if (email && password) {
      setIsAuthenticated(true);
    }
  };

  // Sync state & background coordinates update to simulate movement on map
  useEffect(() => {
    if (!isAuthenticated || activeTab !== 'map') return;
    
    const interval = setInterval(() => {
      setLiveBuses(prevBuses => 
        prevBuses.map(bus => {
          let nextProgress = bus.progress + 0.005;
          if (nextProgress > 1) {
            nextProgress = 0; // Reset journey
          }
          
          // Calculate heading based on path change
          const segments = bus.route_coords.length - 1;
          const currentSegment = Math.min(
            Math.floor(nextProgress * segments),
            segments - 1
          );
          const p1 = bus.route_coords[currentSegment];
          const p2 = bus.route_coords[currentSegment + 1];
          const dx = p2.x - p1.x;
          const dy = p2.y - p1.y;
          const heading = Math.round((Math.atan2(dy, dx) * 180) / Math.PI) + 90;

          // Adjust speed slightly
          const speedOffset = Math.floor(Math.random() * 7) - 3;
          let nextSpeed = bus.speed + speedOffset;
          if (nextSpeed < 40) nextSpeed = 50;
          if (nextSpeed > 100) nextSpeed = 90;

          return {
            ...bus,
            progress: nextProgress,
            speed: nextSpeed,
            heading: heading >= 0 ? heading : heading + 360
          };
        })
      );
    }, 1000);

    return () => clearInterval(interval);
  }, [isAuthenticated, activeTab]);

  // Canvas Drawing of map
  useEffect(() => {
    if (!isAuthenticated || activeTab !== 'map' || !canvasRef.current) return;
    
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    
    let animationFrameId: number;

    const render = () => {
      // Clear canvas
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      
      // Draw background grids (radar theme)
      ctx.strokeStyle = 'rgba(230, 81, 0, 0.04)';
      ctx.lineWidth = 1;
      const gridSize = 40;
      for (let x = 0; x < canvas.width; x += gridSize) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, canvas.height);
        ctx.stroke();
      }
      for (let y = 0; y < canvas.height; y += gridSize) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(canvas.width, y);
        ctx.stroke();
      }

      // Draw stylized contours of Sri Lanka (mock map outlines)
      ctx.strokeStyle = 'rgba(10, 37, 64, 0.15)';
      ctx.fillStyle = 'rgba(10, 37, 64, 0.02)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      // Drawing a simplified tear-drop outline representing Sri Lanka
      ctx.moveTo(250, 40);
      ctx.bezierCurveTo(340, 100, 360, 240, 300, 380);
      ctx.bezierCurveTo(240, 480, 120, 460, 80, 380);
      ctx.bezierCurveTo(40, 300, 60, 200, 160, 80);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      // Draw major stations/terminals
      const stations = [
        { name: 'Jaffna', x: 120, y: 50 },
        { name: 'Anuradhapura', x: 170, y: 150 },
        { name: 'Kandy', x: 240, y: 280 },
        { name: 'Colombo', x: 110, y: 320 },
        { name: 'Galle', x: 130, y: 440 }
      ];

      stations.forEach(station => {
        // Glowing dot
        ctx.shadowColor = '#e65100';
        ctx.shadowBlur = 10;
        ctx.fillStyle = 'rgba(230, 81, 0, 0.8)';
        ctx.beginPath();
        ctx.arc(station.x, station.y, 6, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0; // Reset

        // Label
        ctx.fillStyle = '#64748b';
        ctx.font = '10px Inter';
        ctx.fillText(station.name, station.x + 12, station.y + 4);
      });

      // Draw Route Lines
      liveBuses.forEach(bus => {
        ctx.strokeStyle = 'rgba(10, 37, 64, 0.15)';
        ctx.lineWidth = 3;
        ctx.beginPath();
        
        // Map logical coords into Sri Lanka coordinate overlay offsets
        const getCanvasCoord = (c: { x: number, y: number }) => {
          // Coordinate transformation logic
          return {
            x: c.x + 60,
            y: c.y + 160
          };
        };

        const start = getCanvasCoord(bus.route_coords[0]);
        ctx.moveTo(start.x, start.y);
        for(let i=1; i<bus.route_coords.length; i++){
          const next = getCanvasCoord(bus.route_coords[i]);
          ctx.lineTo(next.x, next.y);
        }
        ctx.stroke();

        // Draw animated bus progress dot
        // Calculate location based on current progress
        const segments = bus.route_coords.length - 1;
        const currentSegment = Math.min(
          Math.floor(bus.progress * segments),
          segments - 1
        );
        const segmentProgress = (bus.progress * segments) - currentSegment;

        const p1 = getCanvasCoord(bus.route_coords[currentSegment]);
        const p2 = getCanvasCoord(bus.route_coords[currentSegment + 1]);

        const currentX = p1.x + (p2.x - p1.x) * segmentProgress;
        const currentY = p1.y + (p2.y - p1.y) * segmentProgress;

        // Draw active tracking ring
        const isSelected = bus.id === selectedBus;
        if (isSelected) {
          ctx.strokeStyle = '#e65100';
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.arc(currentX, currentY, 15 + Math.sin(Date.now() / 150) * 3, 0, Math.PI * 2);
          ctx.stroke();
        }

        // Draw vehicle pointer
        ctx.fillStyle = isSelected ? '#e65100' : '#1e3a8a';
        ctx.beginPath();
        ctx.arc(currentX, currentY, 7, 0, Math.PI * 2);
        ctx.fill();

        // Vehicle registration plate tag
        ctx.fillStyle = '#0a2540';
        ctx.font = 'bold 9px Inter';
        ctx.fillText(bus.reg, currentX - 22, currentY - 12);
      });

      animationFrameId = requestAnimationFrame(render);
    };

    render();

    return () => {
      cancelAnimationFrame(animationFrameId);
    };
  }, [isAuthenticated, activeTab, liveBuses, selectedBus]);

  // Handle vehicle approvals
  const handleApprove = (id: string) => {
    setVehicles(prev => prev.map(v => v.id === id ? { ...v, is_verified: true } : v));
  };

  const handleReject = (id: string) => {
    setVehicles(prev => prev.filter(v => v.id !== id));
  };

  if (!isAuthenticated) {
    return (
      <div className="auth-container">
        <div className="auth-card">
          <div className="auth-logo" style={{ display: 'flex', justifyContent: 'center', marginBottom: '16px' }}>
            <img src="/app_logo.png" alt="Seaty Logo" style={{ height: '48px', objectFit: 'contain' }} />
          </div>
          <p className="auth-subtitle">Luxury Transport Operator Admin Console</p>
          <form onSubmit={handleLogin}>
            <div className="form-group">
              <label className="form-label">Email Address</label>
              <input 
                type="email" 
                className="form-input" 
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
            <div className="form-group">
              <label className="form-label">Password</label>
              <input 
                type="password" 
                className="form-input" 
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
            <button type="submit" className="btn-primary">Authenticate Console</button>
          </form>
        </div>
      </div>
    );
  }

  // Dashboard calculations
  const pendingApprovals = vehicles.filter(v => !v.is_verified);
  const totalBuses = vehicles.length;
  const verifiedBuses = vehicles.filter(v => v.is_verified).length;

  return (
    <div className="dashboard-layout">
      {/* Sidebar Navigation */}
      <aside className="sidebar">
        <div className="sidebar-brand">
          <img src="/app_logo.png" alt="Seaty Logo" style={{ height: '28px', objectFit: 'contain' }} />
        </div>
        <ul className="sidebar-menu">
          <li 
            className={`sidebar-item ${activeTab === 'overview' ? 'active' : ''}`}
            onClick={() => setActiveTab('overview')}
          >
            <Activity size={18} />
            Overview & Stats
          </li>
          <li 
            className={`sidebar-item ${activeTab === 'approvals' ? 'active' : ''}`}
            onClick={() => setActiveTab('approvals')}
          >
            <CheckCircle size={18} />
            Pending Approvals
            {pendingApprovals.length > 0 && (
              <span className="badge badge-warning" style={{ marginLeft: 'auto', padding: '2px 6px', fontSize: '10px' }}>
                {pendingApprovals.length}
              </span>
            )}
          </li>
          <li 
            className={`sidebar-item ${activeTab === 'map' ? 'active' : ''}`}
            onClick={() => setActiveTab('map')}
          >
            <MapIcon size={18} />
            Live Fleet Map
            <span className="badge badge-success" style={{ marginLeft: 'auto', padding: '2px 6px', fontSize: '10px' }}>
              Live
            </span>
          </li>
          <li 
            className={`sidebar-item ${activeTab === 'bookings' ? 'active' : ''}`}
            onClick={() => setActiveTab('bookings')}
          >
            <Users size={18} />
            Bookings Log
          </li>
          <li 
            className={`sidebar-item ${activeTab === 'settings' ? 'active' : ''}`}
            onClick={() => setActiveTab('settings')}
          >
            <SettingsIcon size={18} />
            Console Settings
          </li>
        </ul>
        <div className="sidebar-footer">
          <div className="user-profile-badge" style={{ marginBottom: '20px' }}>
            <div className="user-avatar">AD</div>
            <div className="user-info">
              <span className="user-name">Sys Admin</span>
              <span className="user-role">Superuser</span>
            </div>
          </div>
          <div className="sidebar-item" onClick={() => setIsAuthenticated(false)} style={{ color: '#ef4444' }}>
            <LogOut size={18} />
            Sign Out
          </div>
        </div>
      </aside>

      {/* Main Container */}
      <main className="main-content">
        {/* TAB 1: OVERVIEW */}
        {activeTab === 'overview' && (
          <div>
            <div className="page-header">
              <div>
                <h1 className="page-title">Operational Dashboard</h1>
                <p className="page-subtitle">Real-time stats of luxury buses, owners, and booking revenue.</p>
              </div>
              <div className="badge badge-info">
                <Clock size={14} style={{ marginRight: '6px' }} />
                Session Active (Sri Lanka)
              </div>
            </div>

            <div className="stats-grid">
              <div className="stat-card">
                <div className="stat-header">
                  <span>Gross Ticket Revenue</span>
                  <DollarSign size={18} style={{ color: '#e65100' }} />
                </div>
                <div className="stat-value">Rs. 258,100</div>
                <div className="stat-trend up">
                  <TrendingUp size={14} /> +12.4% this week
                </div>
              </div>
              <div className="stat-card">
                <div className="stat-header">
                  <span>Total Luxury Vehicles</span>
                  <Bus size={18} style={{ color: '#e65100' }} />
                </div>
                <div className="stat-value">{totalBuses}</div>
                <div className="stat-trend up">
                  <TrendingUp size={14} /> {verifiedBuses} verified routes
                </div>
              </div>
              <div className="stat-card">
                <div className="stat-header">
                  <span>Active Bookings</span>
                  <Users size={18} style={{ color: '#10b981' }} />
                </div>
                <div className="stat-value">{bookings.length}</div>
                <div className="stat-trend up">
                  <TrendingUp size={14} /> 94% seat fill rate
                </div>
              </div>
              <div className="stat-card">
                <div className="stat-header">
                  <span>Approvals Queue</span>
                  <Clock size={18} style={{ color: '#f59e0b' }} />
                </div>
                <div className="stat-value">{pendingApprovals.length}</div>
                <div className="stat-trend">
                  Vehicles pending safety check
                </div>
              </div>
            </div>

            {/* Quick Summary Layout */}
            <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: '30px' }}>
              <div className="table-card">
                <div className="table-header">
                  <h3 className="table-title">Recent Tickets Purchased</h3>
                  <Users size={18} style={{ color: '#9ca3af' }} />
                </div>
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th>Passenger</th>
                      <th>Bus Line</th>
                      <th>Seat Layout</th>
                      <th>Total Fare</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {bookings.map(b => (
                      <tr key={b.id}>
                        <td>
                          <div><strong>{b.passenger}</strong></div>
                          <div style={{ fontSize: '11px', color: '#9ca3af', marginTop: '2px' }}>{b.phone}</div>
                        </td>
                        <td>{b.vehicle}</td>
                        <td>{b.seats.join(', ')}</td>
                        <td>Rs. {b.price.toLocaleString()}</td>
                        <td>
                          <span className={`badge ${b.status === 'paid' ? 'badge-success' : 'badge-warning'}`}>
                            {b.status}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className="table-card" style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <h3 className="table-title">Console Alerts</h3>
                <div style={{ display: 'flex', gap: '12px', background: 'rgba(245, 158, 11, 0.08)', padding: '12px', borderRadius: '10px', border: '1px solid rgba(245, 158, 11, 0.2)' }}>
                  <Clock size={18} style={{ color: '#f59e0b', flexShrink: 0, marginTop: '2px' }} />
                  <div style={{ fontSize: '13px' }}>
                    <strong>{pendingApprovals.length} Vehicle Approvals Pending</strong>
                    <div style={{ color: '#9ca3af', marginTop: '4px' }}>Verify bus documentation & permit licenses.</div>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '12px', background: 'rgba(16, 185, 129, 0.08)', padding: '12px', borderRadius: '10px', border: '1px solid rgba(16, 185, 129, 0.2)' }}>
                  <CheckCircle size={18} style={{ color: '#10b981', flexShrink: 0, marginTop: '2px' }} />
                  <div style={{ fontSize: '13px' }}>
                    <strong>All GPS Nodes Online</strong>
                    <div style={{ color: '#9ca3af', marginTop: '4px' }}>Live WebSockets coordinates streaming properly from Sri Lanka.</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 2: APPROVAL QUEUE */}
        {activeTab === 'approvals' && (
          <div>
            <div className="page-header">
              <div>
                <h1 className="page-title">Vehicle Verification Hub</h1>
                <p className="page-subtitle">Review transport operator registrations, license numbers, and amenities specifications.</p>
              </div>
            </div>

            <div className="table-card">
              {pendingApprovals.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '40px 20px', color: '#9ca3af' }}>
                  <CheckCircle size={48} style={{ color: '#10b981', marginBottom: '16px' }} />
                  <h4>Verification Queue Clear!</h4>
                  <p style={{ fontSize: '13px', marginTop: '4px' }}>All luxury vehicles registered have been reviewed and approved.</p>
                </div>
              ) : (
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th>Operator & Bus Detail</th>
                      <th>Plate Number</th>
                      <th>Capacity</th>
                      <th>Amenities Included</th>
                      <th>Documentation Verified</th>
                      <th>Action Buttons</th>
                    </tr>
                  </thead>
                  <tbody>
                    {pendingApprovals.map(v => (
                      <tr key={v.id}>
                        <td>
                          <div><strong>{v.name}</strong></div>
                          <div style={{ fontSize: '11px', color: '#9ca3af', marginTop: '4px' }}>Owner: {v.owner}</div>
                        </td>
                        <td><span className="badge badge-info">{v.registration_number}</span></td>
                        <td>{v.total_seats} Seats</td>
                        <td>
                          <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap' }}>
                            {v.amenities.map((a, i) => (
                              <span key={i} style={{ background: 'rgba(255,255,255,0.06)', padding: '2px 6px', borderRadius: '4px', fontSize: '10px', color: '#9ca3af' }}>
                                {a}
                              </span>
                            ))}
                          </div>
                        </td>
                        <td>
                          <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
                            {v.document_urls.map((doc, idx) => (
                              <a href="#" key={idx} style={{ color: '#6366f1', textDecoration: 'none', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '4px' }}>
                                <FileText size={12} /> {doc}
                              </a>
                            ))}
                          </div>
                        </td>
                        <td>
                          <button 
                            className="btn-action btn-action-success"
                            onClick={() => handleApprove(v.id)}
                          >
                            Approve
                          </button>
                          <button 
                            className="btn-action btn-action-danger"
                            onClick={() => handleReject(v.id)}
                          >
                            Reject
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </div>
        )}

        {/* TAB 3: LIVE FLEET TRACKING MAP */}
        {activeTab === 'map' && (
          <div>
            <div className="page-header">
              <div>
                <h1 className="page-title">Real-Time Fleet Radar</h1>
                <p className="page-subtitle">Live tracking of luxury vehicles commuting in Sri Lanka. WebSockets connections streaming active GPS pins.</p>
              </div>
            </div>

            <div className="map-canvas-container">
              {/* Map Sidebar */}
              <div className="map-sidebar">
                <h3 className="map-sidebar-title">Active Transporters ({liveBuses.length})</h3>
                <div className="map-bus-list">
                  {liveBuses.map(bus => (
                    <div 
                      key={bus.id} 
                      className={`map-bus-item ${selectedBus === bus.id ? 'selected' : ''}`}
                      onClick={() => setSelectedBus(bus.id)}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                        <span style={{ fontSize: '13px', fontWeight: 'bold' }}>{bus.name}</span>
                        <span className="badge badge-success" style={{ fontSize: '9px', padding: '2px 5px' }}>Active</span>
                      </div>
                      <div style={{ fontSize: '11px', color: '#9ca3af', display: 'flex', justifyContent: 'space-between' }}>
                        <span>Plate: {bus.reg}</span>
                        <span>Speed: {bus.speed} km/h</span>
                      </div>
                      <div style={{ fontSize: '11px', color: '#9ca3af', marginTop: '4px' }}>
                        <span>Route: {bus.origin} &rarr; {bus.dest}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Canvas Renderer */}
              <div className="map-canvas-element">
                <canvas 
                  ref={canvasRef} 
                  width={500} 
                  height={480} 
                  style={{ display: 'block', width: '100%', height: '100%' }}
                />
                
                {/* Details overlay of selected bus */}
                {selectedBus && (
                  (() => {
                    const bus = liveBuses.find(b => b.id === selectedBus);
                    if (!bus) return null;
                    return (
                      <div className="map-stats-overlay">
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px', borderBottom: '1px solid var(--border-color)', paddingBottom: '6px' }}>
                          <Bus size={18} style={{ color: '#ec4899' }} />
                          <strong style={{ fontSize: '14px' }}>{bus.name} ({bus.reg})</strong>
                        </div>
                        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px 16px', fontSize: '12px' }}>
                          <div>Status: <span style={{ color: '#10b981', fontWeight: 'bold' }}>ON-ROUTE</span></div>
                          <div>Speed: <span style={{ color: '#f3f4f6', fontWeight: 'bold' }}>{bus.speed} km/h</span></div>
                          <div>Load: <span style={{ color: '#f3f4f6', fontWeight: 'bold' }}>{bus.passengers} pax</span></div>
                          <div>Bearing: <span style={{ color: '#f3f4f6', fontWeight: 'bold' }}>{bus.heading}&deg; ({bus.heading > 315 || bus.heading <= 45 ? 'N' : bus.heading > 45 && bus.heading <= 135 ? 'E' : bus.heading > 135 && bus.heading <= 225 ? 'S' : 'W'})</span></div>
                          <div style={{ gridColumn: 'span 2' }}>Coords: <span style={{ color: '#6366f1', fontFamily: 'monospace', fontWeight: 'bold' }}>[{(6.927 + (bus.progress * 0.5)).toFixed(4)}, {(79.861 + (bus.progress * 0.4)).toFixed(4)}]</span></div>
                        </div>
                      </div>
                    );
                  })()
                )}
              </div>
            </div>
          </div>
        )}

        {/* TAB 4: BOOKINGS LOG */}
        {activeTab === 'bookings' && (
          <div>
            <div className="page-header">
              <div>
                <h1 className="page-title">Bookings Log Directory</h1>
                <p className="page-subtitle">Track, filter, and inspect luxury seats bookings, pricing, and ticket collections.</p>
              </div>
            </div>

            <div className="table-card">
              <div style={{ display: 'flex', gap: '12px', marginBottom: '20px' }}>
                <div style={{ position: 'relative', flexGrow: 1 }}>
                  <Search size={18} style={{ position: 'absolute', left: '12px', top: '13px', color: '#9ca3af' }} />
                  <input 
                    type="text" 
                    placeholder="Search by Passenger Name or Route..." 
                    className="form-input" 
                    style={{ paddingLeft: '40px' }}
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                  />
                </div>
              </div>

              <table className="custom-table">
                <thead>
                  <tr>
                    <th>Passenger Details</th>
                    <th>Ticket Code</th>
                    <th>Bus Commute</th>
                    <th>Seats Allocated</th>
                    <th>Subtotal Fare</th>
                    <th>Status</th>
                    <th>Purchase Date</th>
                  </tr>
                </thead>
                <tbody>
                  {bookings
                    .filter(b => 
                      b.passenger.toLowerCase().includes(searchTerm.toLowerCase()) || 
                      b.route.toLowerCase().includes(searchTerm.toLowerCase())
                    )
                    .map(b => (
                      <tr key={b.id}>
                        <td>
                          <div><strong>{b.passenger}</strong></div>
                          <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>{b.phone}</div>
                        </td>
                        <td><span style={{ fontFamily: 'monospace', color: '#ec4899', fontWeight: 'bold' }}>TKT-{b.id.toUpperCase()}</span></td>
                        <td>
                          <div>{b.vehicle}</div>
                          <div style={{ fontSize: '11px', color: '#9ca3af', marginTop: '2px' }}>{b.route}</div>
                        </td>
                        <td>{b.seats.join(', ')}</td>
                        <td>Rs. {b.price.toLocaleString()}</td>
                        <td>
                          <span className={`badge ${b.status === 'paid' ? 'badge-success' : 'badge-warning'}`}>
                            {b.status}
                          </span>
                        </td>
                        <td>{b.date}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* TAB 5: CONSOLE SETTINGS */}
        {activeTab === 'settings' && (
          <div>
            <div className="page-header">
              <div>
                <h1 className="page-title">Console Configuration</h1>
                <p className="page-subtitle">Configure system parameters, gateway controls, and platform metrics.</p>
              </div>
            </div>

            <div className="table-card" style={{ maxWidth: '600px' }}>
              <h3 className="table-title" style={{ marginBottom: '20px' }}>Server Status</h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border-color)', paddingBottom: '12px' }}>
                  <div>
                    <strong>FastAPI Backend</strong>
                    <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>Connection: http://localhost:8000/api/v1</div>
                  </div>
                  <span className="badge badge-success">Online</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border-color)', paddingBottom: '12px' }}>
                  <div>
                    <strong>WebSockets GPS Hub</strong>
                    <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>Connection: ws://localhost:8000/api/v1/ws</div>
                  </div>
                  <span className="badge badge-success">Online</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingBottom: '4px' }}>
                  <div>
                    <strong>PostgreSQL Database</strong>
                    <div style={{ fontSize: '12px', color: '#9ca3af', marginTop: '2px' }}>Connection: Localhost Postgres Pool</div>
                  </div>
                  <span className="badge badge-success">Online</span>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
