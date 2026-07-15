import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getRoutes, createRoute, deleteRoute } from '../api/client';
import { Route as RouteIcon, Plus, MapPin, Settings } from 'lucide-react';

interface RouteTemplate {
  id: string;
  origin: string;
  destination: string;
  stops: Array<{ name: string; offset_minutes?: number; distance_km?: number }>;
  total_distance: number;
  estimated_duration: string; // Interval format from Postgres
  created_at: string;
}

export default function RoutesPage() {
  const { token } = useAuth();
  const [routes, setRoutes] = useState<RouteTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [activeActionMenuId, setActiveActionMenuId] = useState<string | null>(null);
  
  // New Route Form State
  const [origin, setOrigin] = useState('');
  const [destination, setDestination] = useState('');
  const [distance, setDistance] = useState('120');
  const [durationHours, setDurationHours] = useState('2');
  
  // Stops adding state
  const [stops, setStops] = useState<string[]>([]);
  const [newStop, setNewStop] = useState('');

  const fetchRoutes = async () => {
    if (!token) return;
    setLoading(true);
    try {
      const data = await getRoutes(token) as RouteTemplate[];
      setRoutes(data);
    } catch {
      setRoutes([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchRoutes();
  }, [token]);

  const handleAddStop = () => {
    const stopClean = newStop.trim();
    if (stopClean && !stops.includes(stopClean)) {
      setStops([...stops, stopClean]);
      setNewStop('');
    }
  };

  const handleRemoveStop = (index: number) => {
    setStops(stops.filter((_, i) => i !== index));
  };

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !origin || !destination) return;

    // Convert stops to correct JSON format
    const stopsJson = stops.map((stopName, idx) => ({
      name: stopName,
      offset_minutes: Math.round((parseFloat(durationHours) * 60) * ((idx + 1) / (stops.length + 1))),
      distance_km: Math.round(parseFloat(distance) * ((idx + 1) / (stops.length + 1))),
    }));

    const durationSeconds = Math.round(parseFloat(durationHours) * 3600);

    try {
      await createRoute(token, {
        origin,
        destination,
        total_distance: parseFloat(distance),
        estimated_duration_seconds: durationSeconds,
        stops: stopsJson,
      });
      
      setShowModal(false);
      // Reset form
      setOrigin('');
      setDestination('');
      setDistance('120');
      setDurationHours('2');
      setStops([]);
      
      await fetchRoutes();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to create route template');
    }
  };

  const handleDelete = async (id: string) => {
    if (!token || !window.confirm('Are you sure you want to delete this route template? All future schedules using this route might be affected.')) return;
    try {
      await deleteRoute(token, id);
      await fetchRoutes();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to delete route template');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Route Templates</h1>
          <p className="page-subtitle">Configure pre-defined luxury route templates with boarding/dropping stops for bus operators.</p>
        </div>
        <button 
          className="btn-primary" 
          style={{ width: 'auto', padding: '10px 20px', display: 'flex', alignItems: 'center', gap: '8px' }} 
          onClick={() => setShowModal(true)}
        >
          <Plus size={16} /> Pre-Define Route
        </button>
      </div>

      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading route templates...</div>
        ) : routes.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>
            <RouteIcon size={48} style={{ color: '#9ca3af', marginBottom: '16px' }} />
            <h4>No Route Templates defined yet</h4>
            <p style={{ fontSize: '13px', marginTop: '4px' }}>Click "Pre-Define Route" to configure your first popular bus route.</p>
          </div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Route Template</th>
                <th>Distance</th>
                <th>Estimated Duration</th>
                <th>Intermediate Boarding Stops</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {routes.map(r => (
                <tr key={r.id}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <RouteIcon size={16} style={{ color: '#e65100' }} />
                      <strong>{r.origin} &rarr; {r.destination}</strong>
                    </div>
                  </td>
                  <td>{r.total_distance} km</td>
                  <td>{r.estimated_duration}</td>
                  <td>
                    {r.stops && r.stops.length > 0 ? (
                      <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
                        {r.stops.map((stop, i) => (
                          <span key={i} style={{ 
                            background: 'rgba(230, 81, 0, 0.06)', 
                            border: '1px solid rgba(230, 81, 0, 0.15)',
                            padding: '3px 8px', 
                            borderRadius: '20px', 
                            fontSize: '11px', 
                            color: '#e65100',
                            fontWeight: 600
                          }}>
                            {stop.name}
                          </span>
                        ))}
                      </div>
                    ) : (
                      <span style={{ fontStyle: 'italic', color: '#9ca3af', fontSize: '12px' }}>Direct Route (No stops)</span>
                    )}
                  </td>
                  <td style={{ position: 'relative' }}>
                    <button
                      className="btn-action"
                      style={{
                        padding: '6px 10px',
                        borderRadius: '6px',
                        background: activeActionMenuId === r.id ? 'rgba(10,37,64,0.1)' : 'rgba(0,0,0,0.03)',
                        border: '1px solid rgba(0,0,0,0.08)',
                        color: 'var(--text-main)',
                        cursor: 'pointer',
                        display: 'inline-flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        transition: 'all 0.2s'
                      }}
                      onClick={() => setActiveActionMenuId(activeActionMenuId === r.id ? null : r.id)}
                    >
                      <Settings size={15} style={{ marginRight: '4px' }} /> Actions
                    </button>
                    
                    {activeActionMenuId === r.id && (
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
                              color: '#ef4444',
                              textAlign: 'left',
                              transition: 'background 0.15s'
                            }}
                            onClick={() => {
                              handleDelete(r.id);
                              setActiveActionMenuId(null);
                            }}
                            onMouseEnter={(e) => e.currentTarget.style.background = '#fef2f2'}
                            onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                          >
                            Delete Route
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

      {/* Define Route Modal */}
      {showModal && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)', display: 'flex',
          alignItems: 'center', justifyContent: 'center', zIndex: 1000,
        }}>
          <div style={{
            background: 'white', borderRadius: '16px', padding: '32px', width: '100%',
            maxWidth: '520px', boxShadow: '0 20px 60px rgba(0,0,0,0.15)',
            maxHeight: '90vh', overflowY: 'auto'
          }}>
            <h3 style={{ marginBottom: '20px', fontSize: '18px', fontWeight: 700 }}>Pre-Define Route Template</h3>
            <form onSubmit={handleCreate}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div className="form-group">
                  <label className="form-label">Origin City *</label>
                  <input className="form-input" placeholder="e.g. Colombo Fort" value={origin} onChange={e => setOrigin(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Destination City *</label>
                  <input className="form-input" placeholder="e.g. Galle" value={destination} onChange={e => setDestination(e.target.value)} required />
                </div>
              </div>
              
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div className="form-group">
                  <label className="form-label">Total Distance (km)</label>
                  <input className="form-input" type="number" step="any" value={distance} onChange={e => setDistance(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Est. Duration (Hours)</label>
                  <input className="form-input" type="number" step="any" value={durationHours} onChange={e => setDurationHours(e.target.value)} required />
                </div>
              </div>

              {/* Stops Section */}
              <div className="form-group" style={{ background: '#f8fafc', padding: '16px', borderRadius: '12px', border: '1px solid var(--border-color)', marginBottom: '24px' }}>
                <label className="form-label" style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <MapPin size={13} style={{ color: '#e65100' }} />
                  Intermediate Stops (In Sequence Order)
                </label>
                <div style={{ display: 'flex', gap: '8px', marginTop: '8px', marginBottom: '12px' }}>
                  <input 
                    className="form-input" 
                    placeholder="e.g. Aluthgama" 
                    value={newStop} 
                    onChange={e => setNewStop(e.target.value)}
                    onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); handleAddStop(); } }}
                  />
                  <button 
                    type="button" 
                    onClick={handleAddStop} 
                    style={{
                      background: '#0a2540', color: 'white', border: 'none', borderRadius: '8px',
                      padding: '0 16px', fontWeight: 'bold', cursor: 'pointer'
                    }}
                  >
                    Add
                  </button>
                </div>

                {stops.length > 0 ? (
                  <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
                    {stops.map((stop, idx) => (
                      <span key={idx} style={{
                        background: 'white', border: '1px solid rgba(0,0,0,0.1)',
                        padding: '4px 10px', borderRadius: '20px', fontSize: '12px',
                        display: 'flex', alignItems: 'center', gap: '6px', fontWeight: 600
                      }}>
                        {stop}
                        <span 
                          onClick={() => handleRemoveStop(idx)} 
                          style={{ color: '#ef4444', cursor: 'pointer', fontWeight: 'bold', fontSize: '13px' }}
                        >
                          &times;
                        </span>
                      </span>
                    ))}
                  </div>
                ) : (
                  <span style={{ fontStyle: 'italic', color: '#9ca3af', fontSize: '11px' }}>No intermediate stops added yet.</span>
                )}
              </div>

              <div style={{ display: 'flex', gap: '12px' }}>
                <button type="button" onClick={() => setShowModal(false)} style={{
                  flex: 1, padding: '12px', border: '1px solid rgba(0,0,0,0.1)', borderRadius: '10px',
                  background: 'white', cursor: 'pointer', fontSize: '14px', fontWeight: 600,
                }}>Cancel</button>
                <button type="submit" className="btn-primary" style={{ flex: 1 }}>Save Template</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
