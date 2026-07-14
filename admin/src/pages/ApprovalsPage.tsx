import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getVehicles, approveVehicle, rejectVehicle } from '../api/client';
import { CheckCircle, FileText } from 'lucide-react';

interface Vehicle {
  id: string;
  name: string;
  registration_number: string;
  type: string;
  total_seats: number;
  amenities: string[];
  is_verified: boolean;
  document_urls: string[];
  owner_id: string;
}

export default function ApprovalsPage() {
  const { token } = useAuth();
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchVehicles = async () => {
    if (!token) return;
    setLoading(true);
    try {
      const data = await getVehicles(token) as Vehicle[];
      setVehicles(data);
    } catch {
      setVehicles([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchVehicles(); }, [token]);

  const handleApprove = async (id: string) => {
    if (!token) return;
    try {
      await approveVehicle(token, id);
      await fetchVehicles();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to approve');
    }
  };

  const handleReject = async (id: string) => {
    if (!token) return;
    try {
      await rejectVehicle(token, id);
      await fetchVehicles();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to reject');
    }
  };

  const pending = vehicles.filter(v => !v.is_verified);

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Vehicle Verification Hub</h1>
          <p className="page-subtitle">Review transport operator registrations, license numbers, and amenities specifications.</p>
        </div>
      </div>

      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading vehicles...</div>
        ) : pending.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '40px 20px', color: '#9ca3af' }}>
            <CheckCircle size={48} style={{ color: '#10b981', marginBottom: '16px' }} />
            <h4>Verification Queue Clear!</h4>
            <p style={{ fontSize: '13px', marginTop: '4px' }}>All luxury vehicles registered have been reviewed and approved.</p>
          </div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Vehicle Name</th>
                <th>Plate Number</th>
                <th>Capacity</th>
                <th>Amenities</th>
                <th>Documents</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {pending.map(v => (
                <tr key={v.id}>
                  <td><strong>{v.name}</strong></td>
                  <td><span className="badge badge-info">{v.registration_number}</span></td>
                  <td>{v.total_seats} Seats</td>
                  <td>
                    <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap' }}>
                      {v.amenities.map((a, i) => (
                        <span key={i} style={{ background: 'rgba(0,0,0,0.04)', padding: '2px 6px', borderRadius: '4px', fontSize: '10px', color: '#64748b' }}>
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
                      {v.document_urls.length === 0 && <span style={{ fontSize: '12px', color: '#9ca3af' }}>No docs</span>}
                    </div>
                  </td>
                  <td>
                    <button className="btn-action btn-action-success" onClick={() => handleApprove(v.id)}>Approve</button>
                    <button className="btn-action btn-action-danger" onClick={() => handleReject(v.id)}>Reject</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Show all vehicles below */}
      {vehicles.filter(v => v.is_verified).length > 0 && (
        <div className="table-card" style={{ marginTop: '20px' }}>
          <h3 className="table-title" style={{ marginBottom: '16px' }}>Verified Fleet ({vehicles.filter(v => v.is_verified).length})</h3>
          <table className="custom-table">
            <thead>
              <tr>
                <th>Vehicle</th>
                <th>Registration</th>
                <th>Capacity</th>
                <th>Amenities</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {vehicles.filter(v => v.is_verified).map(v => (
                <tr key={v.id}>
                  <td><strong>{v.name}</strong></td>
                  <td>{v.registration_number}</td>
                  <td>{v.total_seats} seats</td>
                  <td>{v.amenities.join(', ')}</td>
                  <td><span className="badge badge-success">Verified</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
