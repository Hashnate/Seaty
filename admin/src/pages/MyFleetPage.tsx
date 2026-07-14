import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getVehicles, createVehicle, deleteVehicle } from '../api/client';
import { Plus, Trash2, ShieldCheck, ShieldAlert, Bus } from 'lucide-react';

interface VehicleRecord {
  id: string;
  name: string;
  registration_number: string;
  type: string;
  total_seats: number;
  is_verified: boolean;
  amenities: string[];
}

export default function MyFleetPage() {
  const { token } = useAuth();
  const [vehicles, setVehicles] = useState<VehicleRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  const [name, setName] = useState('');
  const [reg, setReg] = useState('');
  const [seats, setSeats] = useState(40);
  const [amenities, setAmenities] = useState<string[]>(['AC', 'WiFi']);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

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

  const handleAddBus = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    setSubmitting(true);

    try {
      await createVehicle(token, {
        name,
        registration_number: reg,
        type: 'bus',
        seat_layout: { rows: Math.ceil(seats / 4), columns: 4, aisle_after_column: 2 },
        total_seats: Number(seats),
        amenities,
        document_urls: []
      });
      setShowAddModal(false);
      setName('');
      setReg('');
      setSeats(40);
      fetchFleet();
    } catch (err: any) {
      setError(err.message || 'Failed to register bus');
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
      <div className="page-header" style={{ display: 'flex', justifyContent: 'between', alignItems: 'center' }}>
        <div>
          <h1 className="page-title">My Fleet Directory</h1>
          <p className="page-subtitle">Add, inspect, and manage luxury passenger transport buses linked to your company.</p>
        </div>
        <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 18px' }}>
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
            <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ marginTop: '16px' }}>Register First Bus</button>
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
                        <span key={ame} style={{ fontSize: '10px', background: 'rgba(255,255,255,0.06)', padding: '2px 8px', borderRadius: '4px' }}>
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
                  <td>
                    <button onClick={() => handleDeleteBus(v.id)} className="btn-danger" style={{ padding: '6px 12px', background: 'transparent', border: 'none', color: '#ef4444' }}>
                      <Trash2 size={16} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showAddModal && (
        <div className="modal-backdrop" style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.5)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000 }}>
          <div className="table-card" style={{ width: '450px', background: '#0f172a', border: '1px solid rgba(255,255,255,0.1)', padding: '24px', borderRadius: '16px' }}>
            <h3 style={{ margin: '0 0 16px 0', fontSize: '18px', color: 'white' }}>Register New Bus</h3>
            {error && <div style={{ color: '#ef4444', marginBottom: '12px', fontSize: '13px' }}>{error}</div>}
            
            <form onSubmit={handleAddBus}>
              <div className="form-group">
                <label className="form-label">Bus Model Name</label>
                <input type="text" className="form-input" placeholder="e.g. Lanka Express Super VIP" value={name} onChange={(e) => setName(e.target.value)} required />
              </div>
              
              <div className="form-group">
                <label className="form-label">Registration Number</label>
                <input type="text" className="form-input" placeholder="e.g. WP-ND-9999" value={reg} onChange={(e) => setReg(e.target.value)} required />
              </div>
              
              <div className="form-group">
                <label className="form-label">Total Seat Count</label>
                <input type="number" className="form-input" min="10" max="60" value={seats} onChange={(e) => setSeats(Number(e.target.value))} required />
              </div>

              <div className="form-group">
                <label className="form-label">Amenities</label>
                <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', marginTop: '6px' }}>
                  {['AC', 'WiFi', 'Charging Ports', 'Reclining Seats'].map(ame => {
                    const active = amenities.includes(ame);
                    return (
                      <button
                        type="button"
                        key={ame}
                        onClick={() => toggleAmenity(ame)}
                        style={{
                          background: active ? '#e65100' : 'rgba(255,255,255,0.05)',
                          color: 'white',
                          border: 'none',
                          padding: '6px 12px',
                          borderRadius: '8px',
                          fontSize: '12px',
                          cursor: 'pointer'
                        }}
                      >
                        {ame}
                      </button>
                    );
                  })}
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '24px' }}>
                <button type="button" className="btn-secondary" onClick={() => setShowAddModal(false)} style={{ padding: '8px 16px' }}>Cancel</button>
                <button type="submit" className="btn-primary" disabled={submitting} style={{ padding: '8px 20px' }}>
                  {submitting ? 'Registering...' : 'Register Bus'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
