import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getTrips, getVehicles, getRoutes, createTrip, deleteTrip } from '../api/client';
import { Plus, Trash2, Calendar, MapPin, DollarSign } from 'lucide-react';

interface TripRecord {
  id: string;
  vehicle_id: string;
  route_id: string;
  departure_time: string;
  price_per_seat: number;
  status: string;
  vehicle?: { name: string; registration_number: string };
  route?: { origin: string; destination: string };
}

interface VehicleRecord {
  id: string;
  name: string;
  registration_number: string;
  is_verified: boolean;
}

interface RouteRecord {
  id: string;
  origin: string;
  destination: string;
}

export default function MyTripsPage() {
  const { token } = useAuth();
  const [trips, setTrips] = useState<TripRecord[]>([]);
  const [vehicles, setVehicles] = useState<VehicleRecord[]>([]);
  const [routes, setRoutes] = useState<RouteRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  
  // Form State
  const [selectedVehicle, setSelectedVehicle] = useState('');
  const [selectedRoute, setSelectedRoute] = useState('');
  const [departureTime, setDepartureTime] = useState('');
  const [price, setPrice] = useState('1600');
  
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const fetchTrips = () => {
    if (!token) return;
    setLoading(true);
    getTrips(token)
      .then(data => setTrips((data as TripRecord[]) || []))
      .catch(() => setTrips([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchTrips();
    if (token) {
      // Fetch verified vehicles only
      getVehicles(token)
        .then(data => setVehicles(((data as VehicleRecord[]) || []).filter(v => v.is_verified)))
        .catch(() => setVehicles([]));
      // Fetch route templates
      getRoutes(token)
        .then(data => setRoutes((data as RouteRecord[]) || []))
        .catch(() => setRoutes([]));
    }
  }, [token]);

  const handleAddTrip = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    
    if (!selectedVehicle) return setError('Please select a verified vehicle');
    if (!selectedRoute) return setError('Please select a route template');
    if (!departureTime) return setError('Please enter a departure time');
    
    setSubmitting(true);

    try {
      // Calculate arrival time (approx 2 hours later)
      const depDate = new Date(departureTime);
      const arrDate = new Date(depDate.getTime() + 2 * 60 * 60 * 1000);

      await createTrip(token, {
        vehicle_id: selectedVehicle,
        route_id: selectedRoute,
        departure_time: depDate.toISOString(),
        arrival_time: arrDate.toISOString(),
        price_per_seat: Number(price)
      });
      
      setShowAddModal(false);
      setSelectedVehicle('');
      setSelectedRoute('');
      setDepartureTime('');
      setPrice('1600');
      fetchTrips();
    } catch (err: any) {
      setError(err.message || 'Failed to schedule trip');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteTrip = async (id: string) => {
    if (!token || !window.confirm('Are you sure you want to cancel and delete this scheduled trip?')) return;
    try {
      await deleteTrip(token, id);
      fetchTrips();
    } catch (err: any) {
      alert(err.message || 'Failed to delete scheduled trip');
    }
  };

  return (
    <div>
      <div className="page-header" style={{ display: 'flex', justifyContent: 'between', alignItems: 'center' }}>
        <div>
          <h1 className="page-title">Trip Timings Scheduler</h1>
          <p className="page-subtitle">Schedule bus departures and set seat pricing using route templates.</p>
        </div>
        <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 18px' }}>
          <Plus size={16} /> Schedule Trip
        </button>
      </div>

      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading schedules...</div>
        ) : trips.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '60px', color: '#9ca3af' }}>
            <Calendar size={48} style={{ marginBottom: '16px', color: 'rgba(255,255,255,0.1)' }} />
            <div>No active trips scheduled yet.</div>
            <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ marginTop: '16px' }}>Schedule Your First Trip</button>
          </div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Bus Info</th>
                <th>Route Name</th>
                <th>Departure Time</th>
                <th>Seat Fare</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {trips.map(t => (
                <tr key={t.id}>
                  <td>
                    <div style={{ fontWeight: 'bold' }}>{t.vehicle?.name || '—'}</div>
                    <div style={{ fontSize: '12px', color: '#9ca3af', fontFamily: 'monospace', marginTop: '2px' }}>{t.vehicle?.registration_number}</div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px', fontWeight: '500' }}>
                      <MapPin size={14} color="#e65100" />
                      {t.route ? `${t.route.origin} → ${t.route.destination}` : '—'}
                    </div>
                  </td>
                  <td>
                    {new Date(t.departure_time).toLocaleString('en-LK', { dateStyle: 'medium', timeStyle: 'short' })}
                  </td>
                  <td>
                    <div style={{ fontWeight: 'bold', color: '#e65100' }}>Rs. {t.price_per_seat.toLocaleString()}</div>
                  </td>
                  <td>
                    <span className={`badge ${t.status === 'scheduled' ? 'badge-success' : 'badge-warning'}`}>
                      {t.status}
                    </span>
                  </td>
                  <td>
                    <button onClick={() => handleDeleteTrip(t.id)} className="btn-danger" style={{ padding: '6px 12px', background: 'transparent', border: 'none', color: '#ef4444' }}>
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
            <h3 style={{ margin: '0 0 16px 0', fontSize: '18px', color: 'white' }}>Schedule New Trip</h3>
            {error && <div style={{ color: '#ef4444', marginBottom: '12px', fontSize: '13px' }}>{error}</div>}
            
            <form onSubmit={handleAddTrip}>
              <div className="form-group">
                <label className="form-label">Select Verified Bus</label>
                <select className="form-input" style={{ backgroundColor: '#1e293b', color: 'white' }} value={selectedVehicle} onChange={(e) => setSelectedVehicle(e.target.value)} required>
                  <option value="">-- Choose Bus --</option>
                  {vehicles.map(v => (
                    <option key={v.id} value={v.id}>{v.name} ({v.registration_number})</option>
                  ))}
                </select>
              </div>
              
              <div className="form-group">
                <label className="form-label">Select Route Template</label>
                <select className="form-input" style={{ backgroundColor: '#1e293b', color: 'white' }} value={selectedRoute} onChange={(e) => setSelectedRoute(e.target.value)} required>
                  <option value="">-- Choose Route --</option>
                  {routes.map(r => (
                    <option key={r.id} value={r.id}>{r.origin} to {r.destination}</option>
                  ))}
                </select>
              </div>
              
              <div className="form-group">
                <label className="form-label">Departure Date & Time</label>
                <input type="datetime-local" className="form-input" value={departureTime} onChange={(e) => setDepartureTime(e.target.value)} required />
              </div>
              
              <div className="form-group">
                <label className="form-label">Price per Seat (LKR)</label>
                <div style={{ position: 'relative' }}>
                  <span style={{ position: 'absolute', left: '12px', top: '12px', color: '#e65100', fontWeight: 'bold' }}>Rs.</span>
                  <input type="number" className="form-input" style={{ paddingLeft: '40px' }} min="100" max="10000" value={price} onChange={(e) => setPrice(e.target.value)} required />
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '24px' }}>
                <button type="button" className="btn-secondary" onClick={() => setShowAddModal(false)} style={{ padding: '8px 16px' }}>Cancel</button>
                <button type="submit" className="btn-primary" disabled={submitting} style={{ padding: '8px 20px' }}>
                  {submitting ? 'Scheduling...' : 'Schedule Trip'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
