import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import CustomSelect from '../components/CustomSelect';
import { getVehicles, createVehicle, deleteVehicle, updateVehicle } from '../api/client';
import { Plus, ShieldCheck, ShieldAlert, Bus, Wifi, Plug, Tv, Armchair, Users, Briefcase, Snowflake, Settings } from 'lucide-react';

interface VehicleRecord {
  id: string;
  name: string;
  registration_number: string;
  type: string;
  total_seats: number;
  is_verified: boolean;
  amenities: string[];
}

const getAmenityIcon = (name: string, size = 14) => {
  const n = name.toLowerCase();
  if (n.includes('wifi')) return <Wifi size={size} />;
  if (n.includes('charge') || n.includes('charging') || n.includes('plug') || n.includes('outlet')) return <Plug size={size} />;
  if (n.includes('tv') || n.includes('screen') || n.includes('video') || n.includes('hd tv')) return <Tv size={size} />;
  if (n.includes('seat') || n.includes('recline') || n.includes('reclining')) return <Armchair size={size} />;
  if (n.includes('restroom') || n.includes('toilet') || n.includes('wc')) return <Users size={size} />;
  if (n.includes('luggage') || n.includes('baggage') || n.includes('bag') || n.includes('space')) return <Briefcase size={size} />;
  if (n.includes('ac') || n.includes('air') || n.includes('cool') || n.includes('snowflake')) return <Snowflake size={size} />;
  return null;
};

export default function MyFleetPage() {
  const { token } = useAuth();
  const [vehicles, setVehicles] = useState<VehicleRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  const [name, setName] = useState('');
  const [reg, setReg] = useState('');
  const [seats, setSeats] = useState(40);
  const [columns, setColumns] = useState(4);
  const [aisleAfter, setAisleAfter] = useState(2);
  const [rows, setRows] = useState(10);
  const [customSeats, setCustomSeats] = useState<{ row: number; col: number; label: string }[]>([]);
  const [amenities, setAmenities] = useState<string[]>(['AC', 'WiFi']);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const [preset, setPreset] = useState('expressway');
  const [isOpenPreset, setIsOpenPreset] = useState(false);
  const [editingVehicleId, setEditingVehicleId] = useState<string | null>(null);
  const [activeActionMenuId, setActiveActionMenuId] = useState<string | null>(null);

  const applyPreset = (presetType: string) => {
    setPreset(presetType);
    if (presetType === 'custom') {
      setCustomSeats([]);
      return;
    }

    let newRows = 12;
    let newCols = 4;
    let newAisle = 2;

    if (presetType === 'expressway') {
      newRows = 12;
      newCols = 4;
      newAisle = 2;
    } else if (presetType === 'semiluxury') {
      newRows = 12;
      newCols = 5;
      newAisle = 2;
    } else if (presetType === 'rosa') {
      newRows = 10;
      newCols = 3;
      newAisle = 2;
    }

    setRows(newRows);
    setColumns(newCols);
    setAisleAfter(newAisle);

    const newSeats = [];
    const gridColumnsCount = newAisle > 0 ? newCols + 1 : newCols;
    for (let r = 1; r <= newRows; r++) {
      for (let c = 0; c < gridColumnsCount; c++) {
        if (newAisle > 0 && c === newAisle && r < newRows) {
          continue; // Skip aisle except for last row
        }
        const colLetter = String.fromCharCode(65 + c);
        newSeats.push({ row: r, col: c, label: `${colLetter}${r}` });
      }
    }
    setCustomSeats(newSeats);
  };

  useEffect(() => {
    if (showAddModal && !editingVehicleId) {
      setName('');
      setReg('');
      setAmenities(['AC', 'WiFi']);
      setIsOpenPreset(false);
      applyPreset('expressway');
    }
  }, [showAddModal, editingVehicleId]);

  // Sync total seat count state with actual custom layout length
  useEffect(() => {
    setSeats(customSeats.length);
  }, [customSeats]);

  const fetchFleet = () => {
    if (!token) return;
    setLoading(true);
    getVehicles(token)
      .then(data => setVehicles((data as VehicleRecord[]) || []))
      .catch(() => setVehicles([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchFleet();
  }, [token]);

  const handleEditClick = (v: VehicleRecord) => {
    setEditingVehicleId(v.id);
    setName(v.name);
    setReg(v.registration_number);
    setSeats(v.total_seats);
    
    const layout = (v as any).seat_layout || {};
    setRows(layout.rows || 10);
    setColumns(layout.columns || 4);
    setAisleAfter(layout.aisle_after_column ?? 2);
    setCustomSeats(layout.seats || []);
    setAmenities(v.amenities || []);
    setPreset('custom');
    setShowAddModal(true);
  };

  const handleAddBus = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    setSubmitting(true);

    const vehicleData = {
      name,
      registration_number: reg,
      type: 'bus',
      seat_layout: { 
        rows: Number(rows), 
        columns: Number(columns), 
        aisle_after_column: Number(aisleAfter),
        seats: customSeats 
      },
      total_seats: Number(seats),
      amenities,
      document_urls: []
    };

    try {
      if (editingVehicleId) {
        await updateVehicle(token, editingVehicleId, vehicleData);
      } else {
        await createVehicle(token, vehicleData);
      }
      setShowAddModal(false);
      setEditingVehicleId(null);
      setName('');
      setReg('');
      setSeats(40);
      setColumns(4);
      setAisleAfter(2);
      fetchFleet();
    } catch (err: any) {
      setError(err.message || (editingVehicleId ? 'Failed to update bus' : 'Failed to register bus'));
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteBus = async (id: string) => {
    if (!token || !window.confirm('Are you sure you want to remove this vehicle from your fleet?')) return;
    try {
      await deleteVehicle(token, id);
      fetchFleet();
    } catch (err: any) {
      alert(err.message || 'Failed to remove bus');
    }
  };

  const toggleAmenity = (ame: string) => {
    setAmenities(prev =>
      prev.includes(ame) ? prev.filter(x => x !== ame) : [...prev, ame]
    );
  };

  return (
    <div>
      <div className="page-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 className="page-title">My Fleet Directory</h1>
          <p className="page-subtitle">Add, inspect, and manage luxury passenger transport buses linked to your company.</p>
        </div>
        <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 18px', width: 'auto' }}>
          <Plus size={16} /> Add Bus
        </button>
      </div>

      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading fleet...</div>
        ) : vehicles.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '60px', color: '#9ca3af' }}>
            <Bus size={48} style={{ marginBottom: '16px', color: 'rgba(255,255,255,0.1)' }} />
            <div>No vehicles registered under your company yet.</div>
            <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ marginTop: '16px', width: 'auto' }}>Register First Bus</button>
          </div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Bus Details</th>
                <th>Registration</th>
                <th>Seat Capacity</th>
                <th>Amenities</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {vehicles.map(v => (
                <tr key={v.id}>
                  <td>
                    <div style={{ fontWeight: 'bold' }}>{v.name}</div>
                  </td>
                  <td>
                    <span style={{ fontFamily: 'monospace', fontWeight: 'bold', fontSize: '13px' }}>{v.registration_number}</span>
                  </td>
                  <td>{v.total_seats} Seats</td>
                  <td>
                    <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
                      {v.amenities.map(ame => (
                        <span key={ame} style={{ fontSize: '11px', background: 'rgba(10, 37, 64, 0.06)', padding: '4px 8px', borderRadius: '6px', display: 'inline-flex', alignItems: 'center', gap: '6px', color: 'var(--text-main)' }}>
                          {getAmenityIcon(ame, 12)}
                          {ame}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td>
                    {v.is_verified ? (
                      <span className="badge badge-success" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                        <ShieldCheck size={12} /> Verified
                      </span>
                    ) : (
                      <span className="badge badge-warning" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                        <ShieldAlert size={12} /> Pending verification
                      </span>
                    )}
                  </td>
                  <td style={{ position: 'relative' }}>
                    <button
                      className="btn-action"
                      style={{
                        padding: '6px 10px',
                        borderRadius: '6px',
                        background: activeActionMenuId === v.id ? 'rgba(10,37,64,0.1)' : 'rgba(0,0,0,0.03)',
                        border: '1px solid rgba(0,0,0,0.08)',
                        color: 'var(--text-main)',
                        cursor: 'pointer',
                        display: 'inline-flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        transition: 'all 0.2s'
                      }}
                      onClick={() => setActiveActionMenuId(activeActionMenuId === v.id ? null : v.id)}
                    >
                      <Settings size={15} style={{ marginRight: '4px' }} /> Actions
                    </button>
                    
                    {activeActionMenuId === v.id && (
                      <>
                        <div
                          style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, zIndex: 998 }}
                          onClick={() => setActiveActionMenuId(null)}
                        />
                        
                        <div
                          style={{
                            position: 'absolute',
                            right: 0,
                            top: '100%',
                            marginTop: '4px',
                            background: 'white',
                            border: '1px solid rgba(0,0,0,0.08)',
                            borderRadius: '8px',
                            boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
                            zIndex: 999,
                            minWidth: '130px',
                            overflow: 'hidden'
                          }}
                        >
                          <div
                            style={{
                              padding: '8px 12px',
                              cursor: 'pointer',
                              fontSize: '13px',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '8px',
                              color: 'var(--text-main)',
                              textAlign: 'left',
                              transition: 'background 0.15s'
                            }}
                            onClick={() => {
                              handleEditClick(v);
                              setActiveActionMenuId(null);
                            }}
                            onMouseEnter={(e) => e.currentTarget.style.background = '#f8fafc'}
                            onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                          >
                            Edit Layout
                          </div>
                          <div
                            style={{
                              padding: '8px 12px',
                              cursor: 'pointer',
                              fontSize: '13px',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '8px',
                              color: '#ef4444',
                              borderTop: '1px solid rgba(0,0,0,0.04)',
                              textAlign: 'left',
                              transition: 'background 0.15s'
                            }}
                            onClick={() => {
                              handleDeleteBus(v.id);
                              setActiveActionMenuId(null);
                            }}
                            onMouseEnter={(e) => e.currentTarget.style.background = '#fef2f2'}
                            onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                          >
                            Remove Bus
                          </div>
                        </div>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showAddModal && (
        <div className="modal-backdrop" style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(15, 23, 42, 0.4)', display: 'flex', justifyContent: 'center', alignItems: 'flex-start', zIndex: 1000, backdropFilter: 'blur(8px)', overflowY: 'auto', padding: '40px 20px' }}>
          <div className="table-card" style={{ width: '960px', maxWidth: '95vw', background: '#ffffff', border: '1px solid var(--border-color)', padding: '28px', borderRadius: '24px', boxShadow: '0 24px 48px -12px rgba(10, 37, 64, 0.18)', margin: 'auto' }}>
            <h3 style={{ margin: '0 0 20px 0', fontSize: '22px', fontWeight: 800, color: 'var(--text-dark)', display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Bus style={{ color: 'var(--color-primary)' }} /> {editingVehicleId ? 'Edit Bus & Design Layout' : 'Register New Bus & Design Layout'}
            </h3>
            {error && <div style={{ color: '#ef4444', marginBottom: '16px', fontSize: '13px', background: 'rgba(239, 68, 68, 0.08)', padding: '8px 12px', borderRadius: '8px', border: '1px solid rgba(239, 68, 68, 0.2)' }}>{error}</div>}
            
            <form onSubmit={handleAddBus} style={{ display: 'grid', gridTemplateColumns: '400px 1fr', gap: '28px' }}>
              {/* Left Panel: Inputs */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <div className="form-group">
                  <label className="form-label">Bus Model Name</label>
                  <input type="text" className="form-input" placeholder="e.g. Lanka Express Super VIP" value={name} onChange={(e) => setName(e.target.value)} required />
                </div>
                
                <div className="form-group">
                  <label className="form-label">Registration Number</label>
                  <input type="text" className="form-input" placeholder="e.g. WP-ND-9999" value={reg} onChange={(e) => setReg(e.target.value)} required />
                </div>

                <div className="form-group" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                  <div>
                    <label className="form-label">Grid Rows</label>
                    <input
                      type="number"
                      className="form-input"
                      min="3"
                      max="15"
                      value={rows}
                      onChange={(e) => {
                        const newRows = Math.max(3, Math.min(15, Number(e.target.value)));
                        setRows(newRows);
                        // Filter out seats that are beyond the new rows limit
                        setCustomSeats(prev => prev.filter(s => s.row <= newRows));
                      }}
                      required
                    />
                  </div>
                  <div>
                    <label className="form-label">Total Seats (Read-only)</label>
                    <input type="text" className="form-input" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border-color)', cursor: 'not-allowed', color: 'var(--color-primary)', fontWeight: 'bold' }} value={`${seats} Seats`} readOnly />
                  </div>
                </div>
                
                <div className="form-group" style={{ display: 'flex', gap: '12px' }}>
                  <div style={{ flex: 1 }}>
                    <label className="form-label">Seat Columns</label>
                    <CustomSelect
                      options={[2, 3, 4, 5].map(c => ({ value: c, label: `${c} Columns` }))}
                      value={columns}
                      onChange={(val) => {
                        const cols = Number(val);
                        setColumns(cols);
                        if (aisleAfter >= cols) {
                          setAisleAfter(cols - 1);
                        }
                        // Filter out seats beyond columns limit
                        setCustomSeats(prev => prev.filter(s => s.col < cols));
                      }}
                    />
                  </div>
                  <div style={{ flex: 1 }}>
                    <label className="form-label">Aisle Position</label>
                    <CustomSelect
                      options={[
                        { value: 0, label: 'No Aisle' },
                        ...Array.from({ length: columns - 1 }, (_, i) => i + 1).map(pos => ({
                          value: pos,
                          label: `After Col ${pos}`
                        }))
                      ]}
                      value={aisleAfter}
                      onChange={(val) => setAisleAfter(Number(val))}
                    />
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label">Amenities</label>
                  <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginTop: '6px' }}>
                    {['AC', 'WiFi', 'Charging Ports', 'Reclining Seats', 'HD TV Screens', 'Restrooms', 'Luggage Space'].map(ame => {
                      const active = amenities.includes(ame);
                      return (
                        <button
                          type="button"
                          key={ame}
                          onClick={() => toggleAmenity(ame)}
                          style={{
                            background: active ? 'var(--color-primary)' : 'var(--bg-secondary)',
                            color: active ? 'white' : 'var(--text-muted)',
                            border: active ? '1px solid var(--color-primary)' : '1px solid var(--border-color)',
                            padding: '8px 12px',
                            borderRadius: '8px',
                            fontSize: '12px',
                            cursor: 'pointer',
                            transition: 'all 0.15s ease',
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '6px'
                          }}
                        >
                          {getAmenityIcon(ame, 14)}
                          {ame}
                        </button>
                      );
                    })}
                  </div>
                </div>

                <div style={{ display: 'flex', gap: '12px', marginTop: 'auto', paddingTop: '20px' }}>
                  <button type="button" className="btn-secondary" onClick={() => { setShowAddModal(false); setEditingVehicleId(null); }} style={{ flex: 1, marginTop: 0, padding: '12px', fontSize: '14px' }}>Cancel</button>
                  <button type="submit" className="btn-primary" disabled={submitting || seats === 0} style={{ flex: 1, marginTop: 0, padding: '12px', border: '1px solid transparent', fontSize: '14px' }}>
                    {submitting ? (editingVehicleId ? 'Saving...' : 'Registering...') : (editingVehicleId ? 'Save Changes' : 'Register Bus')}
                  </button>
                </div>
              </div>

              {/* Right Panel: Interactive Layout Simulator */}
              <div style={{ display: 'flex', flexDirection: 'column', background: 'var(--bg-secondary)', border: '1px solid var(--border-color)', borderRadius: '16px', padding: '20px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                  <div>
                    <h4 style={{ margin: 0, color: 'var(--text-dark)', fontSize: '15px', fontWeight: 600 }}>Visual Cabin Layout Builder</h4>
                    <p style={{ margin: '2px 0 0 0', fontSize: '11px', color: 'var(--text-muted)' }}>
                      Drag the template to grid cells, or click cells to toggle seats.
                    </p>
                  </div>
                  <div style={{ padding: '6px 12px', background: 'rgba(37, 99, 235, 0.08)', border: '1px solid rgba(37, 99, 235, 0.15)', borderRadius: '8px', color: 'var(--color-primary)', fontSize: '12px', fontWeight: 600 }}>
                    Seats placed: {seats}
                  </div>
                </div>

                {/* Predefined Templates */}
                <div className="form-group" style={{ marginBottom: '16px', position: 'relative' }}>
                  <label className="form-label">Load Layout Template</label>
                  
                  {/* Selector Box */}
                  <div
                    onClick={() => setIsOpenPreset(!isOpenPreset)}
                    style={{
                      width: '100%',
                      padding: '12px 16px',
                      background: '#ffffff',
                      border: isOpenPreset ? '1.5px solid var(--color-primary)' : '1px solid var(--border-color)',
                      borderRadius: '10px',
                      color: 'var(--text-dark)',
                      fontSize: '15px',
                      cursor: 'pointer',
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      userSelect: 'none',
                      boxShadow: isOpenPreset ? '0 0 12px rgba(37, 99, 235, 0.12)' : 'none',
                      transition: 'all 0.15s ease'
                    }}
                  >
                    <span>
                      {preset === 'expressway' && 'Expressway Coach (2x2 Layout - 49 Seats)'}
                      {preset === 'semiluxury' && 'Ashok Leyland Semi-Luxury (2x3 Layout - 61 Seats)'}
                      {preset === 'rosa' && 'Toyota Rosa Mini Bus (2x1 Layout - 31 Seats)'}
                      {preset === 'custom' && 'Blank Custom Layout (Start Empty)'}
                    </span>
                    <span style={{ fontSize: '10px', color: 'var(--text-muted)', transition: 'transform 0.2s', transform: isOpenPreset ? 'rotate(180deg)' : 'rotate(0deg)' }}>
                      ▼
                    </span>
                  </div>

                  {/* Dropdown Options List */}
                  {isOpenPreset && (
                    <div
                      style={{
                        position: 'absolute',
                        top: '100%',
                        left: 0,
                        right: 0,
                        marginTop: '6px',
                        background: '#ffffff',
                        border: '1px solid var(--border-color)',
                        borderRadius: '10px',
                        boxShadow: '0 10px 25px -5px rgba(0, 0, 0, 0.08)',
                        zIndex: 1010,
                        overflow: 'hidden'
                      }}
                    >
                      {[
                        { value: 'expressway', label: 'Expressway Coach (2x2 Layout - 49 Seats)' },
                        { value: 'semiluxury', label: 'Ashok Leyland Semi-Luxury (2x3 Layout - 61 Seats)' },
                        { value: 'rosa', label: 'Toyota Rosa Mini Bus (2x1 Layout - 31 Seats)' },
                        { value: 'custom', label: 'Blank Custom Layout (Start Empty)' }
                      ].map(opt => {
                        const isSelected = preset === opt.value;
                        return (
                          <div
                            key={opt.value}
                            onClick={() => {
                              applyPreset(opt.value);
                              setIsOpenPreset(false);
                            }}
                            onMouseEnter={(e) => {
                              if (!isSelected) {
                                e.currentTarget.style.background = 'rgba(37, 99, 235, 0.05)';
                              }
                            }}
                            onMouseLeave={(e) => {
                              if (!isSelected) {
                                e.currentTarget.style.background = 'transparent';
                              }
                            }}
                            style={{
                              padding: '12px 16px',
                              background: isSelected ? 'var(--color-primary)' : 'transparent',
                              color: isSelected ? 'white' : 'var(--text-dark)',
                              cursor: 'pointer',
                              fontSize: '14px',
                              fontWeight: isSelected ? 600 : 400,
                              transition: 'all 0.15s ease'
                            }}
                          >
                            {opt.label}
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>

                {/* Toolbox */}
                <div style={{ display: 'flex', gap: '14px', alignItems: 'center', padding: '12px', background: '#ffffff', border: '1px solid var(--border-color)', borderRadius: '10px', marginBottom: '16px' }}>
                  <div
                    draggable
                    onDragStart={(e) => {
                      e.dataTransfer.setData('drag-type', 'new-seat');
                    }}
                    style={{
                      padding: '8px 12px',
                      background: 'var(--color-primary)',
                      borderRadius: '8px',
                      color: 'white',
                      fontWeight: 700,
                      cursor: 'grab',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '6px',
                      fontSize: '12px',
                      boxShadow: '0 4px 10px rgba(37, 99, 235, 0.15)',
                      flexShrink: 0
                    }}
                  >
                    <Bus size={13} /> Drag Seat
                  </div>
                  <div style={{ 
                    display: 'flex', 
                    alignItems: 'flex-start', 
                    gap: '4px', 
                    fontSize: '11px', 
                    color: 'var(--text-muted)', 
                    lineHeight: '1.4' 
                  }}>
                    <span style={{ fontSize: '12px', lineHeight: 1 }}>💡</span>
                    <span>Tip: Dragging existing seats lets you rearrange them.</span>
                  </div>
                </div>

                {/* Bus Body Simulator */}
                <div style={{ flex: 1, overflowY: 'auto', maxHeight: '420px', padding: '20px 40px', background: 'rgba(10, 37, 64, 0.02)', borderRadius: '12px', border: '1px solid var(--border-color)', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                  {/* Bus Front Cap (Steering wheel and Driver section) */}
                  <div style={{ width: '100%', maxWidth: '320px', height: '50px', background: '#ffffff', border: '2px solid var(--border-color)', borderBottom: 'none', borderRadius: '40px 40px 0 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0 28px', color: 'var(--text-muted)', marginBottom: '8px', flexShrink: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', fontWeight: 600 }}>
                      <span style={{ width: '8px', height: '8px', background: 'var(--color-success)', borderRadius: '50%' }}></span> Front / Driver
                    </div>
                    {/* Visual steering wheel */}
                    <div style={{ width: '22px', height: '22px', borderRadius: '50%', border: '4px double var(--border-color)', display: 'flex', justifyContent: 'center', alignItems: 'center' }}>
                      <div style={{ width: '4px', height: '4px', background: 'var(--text-muted)', borderRadius: '50%' }}></div>
                    </div>
                  </div>

                  {/* Grid Canvas */}
                  {(() => {
                    const gridColumnsCount = aisleAfter > 0 ? columns + 1 : columns;
                    return (
                      <div
                        style={{
                          width: '100%',
                          maxWidth: '320px',
                          display: 'grid',
                          gridTemplateColumns: `repeat(${gridColumnsCount}, 1fr)`,
                          gap: '8px',
                          padding: '16px',
                          background: '#ffffff',
                          border: '2px solid var(--border-color)',
                          borderRadius: '0 0 20px 20px',
                          minHeight: '280px',
                          flexShrink: 0
                        }}
                      >
                        {Array.from({ length: rows }).map((_, rIdx) => {
                          const r = rIdx + 1;
                          return Array.from({ length: gridColumnsCount }).map((_, cIdx) => {
                            const isAisle = aisleAfter > 0 && cIdx === aisleAfter;
                            const seat = customSeats.find(s => s.row === r && s.col === cIdx);
                            
                            return (
                              <div
                                key={`cell-${r}-${cIdx}`}
                                onDragOver={(e) => e.preventDefault()}
                                onDrop={(e) => {
                                  e.preventDefault();
                                  const dragType = e.dataTransfer.getData('drag-type');
                                  if (dragType === 'new-seat') {
                                    if (!seat) {
                                      const colLetter = String.fromCharCode(65 + cIdx);
                                      setCustomSeats(prev => [...prev, { row: r, col: cIdx, label: `${colLetter}${r}` }]);
                                    }
                                  } else if (dragType === 'move-seat') {
                                    const fromRow = Number(e.dataTransfer.getData('from-row'));
                                    const fromCol = Number(e.dataTransfer.getData('from-col'));
                                    if (fromRow !== r || fromCol !== cIdx) {
                                      setCustomSeats(prev => {
                                        const filtered = prev.filter(s => !(s.row === fromRow && s.col === fromCol));
                                        const colLetter = String.fromCharCode(65 + cIdx);
                                        return [...filtered, { row: r, col: cIdx, label: `${colLetter}${r}` }];
                                      });
                                    }
                                  }
                                }}
                                onClick={() => {
                                  if (seat) {
                                    setCustomSeats(prev => prev.filter(s => !(s.row === r && s.col === cIdx)));
                                  } else {
                                    const colLetter = String.fromCharCode(65 + cIdx);
                                    setCustomSeats(prev => [...prev, { row: r, col: cIdx, label: `${colLetter}${r}` }]);
                                  }
                                }}
                                style={{
                                  height: '36px',
                                  border: seat ? 'none' : isAisle ? '1px dashed rgba(10, 37, 64, 0.05)' : '1px dashed rgba(10, 37, 64, 0.15)',
                                  borderRadius: '6px',
                                  background: seat ? 'var(--color-primary)' : isAisle ? 'rgba(10, 37, 64, 0.01)' : 'transparent',
                                  boxShadow: seat ? 'inset 0 -2px 0 rgba(0,0,0,0.2), 0 4px 10px rgba(37,99,235,0.15)' : 'none',
                                  display: 'flex',
                                  justifyContent: 'center',
                                  alignItems: 'center',
                                  cursor: 'pointer',
                                  color: seat ? 'white' : isAisle ? 'rgba(10, 37, 64, 0.2)' : 'rgba(10, 37, 64, 0.3)',
                                  fontWeight: 700,
                                  fontSize: '10px',
                                  transition: 'all 0.15s ease',
                                  userSelect: 'none'
                                }}
                                draggable={!!seat}
                                onDragStart={(e) => {
                                  e.dataTransfer.setData('drag-type', 'move-seat');
                                  e.dataTransfer.setData('from-row', String(r));
                                  e.dataTransfer.setData('from-col', String(cIdx));
                                }}
                              >
                                {seat ? seat.label : isAisle ? '|' : '+'}
                              </div>
                            );
                          });
                        })}
                      </div>
                    );
                  })()}
                </div>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
