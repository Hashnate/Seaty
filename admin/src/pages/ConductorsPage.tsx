import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getConductors, createConductor, deleteConductor } from '../api/client';
import { Plus, Users, Mail, Phone, UserCheck, Settings } from 'lucide-react';

interface ConductorRecord {
  id: string;
  full_name: string;
  email: string;
  phone_number: string;
  role: string;
}

export default function ConductorsPage() {
  const { token } = useAuth();
  const [conductors, setConductors] = useState<ConductorRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  const [activeActionMenuId, setActiveActionMenuId] = useState<string | null>(null);
  
  // Form State
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const fetchConductors = () => {
    if (!token) return;
    setLoading(true);
    getConductors(token)
      .then(data => setConductors((data as ConductorRecord[]) || []))
      .catch(() => setConductors([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchConductors();
  }, [token]);

  const handleAddConductor = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    
    if (!name.trim()) return setError('Please enter staff name');
    if (!email.trim()) return setError('Please enter staff email');
    if (!phone.trim()) return setError('Please enter staff phone number');
    if (!password.trim() || password.length < 6) return setError('Password must be at least 6 characters');
    
    setSubmitting(true);

    try {
      await createConductor(token, {
        full_name: name.trim(),
        email: email.trim(),
        phone_number: phone.trim(),
        password: password.trim()
      });
      
      setShowAddModal(false);
      setName('');
      setEmail('');
      setPhone('');
      setPassword('');
      fetchConductors();
    } catch (err: any) {
      setError(err.message || 'Failed to add staff member');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteConductor = async (id: string) => {
    if (!token || !window.confirm('Are you sure you want to remove this staff member from your company?')) return;
    try {
      await deleteConductor(token, id);
      fetchConductors();
    } catch (err: any) {
      alert(err.message || 'Failed to delete staff member');
    }
  };

  return (
    <div>
      <div className="page-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 className="page-title">Company Conductors & Staff</h1>
          <p className="page-subtitle">Add and manage drivers, conductors, and checkers authorized to log in to mobile services.</p>
        </div>
        <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 18px', width: 'auto' }}>
          <Plus size={16} /> Add Conductor / Driver
        </button>
      </div>

      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading staff...</div>
        ) : conductors.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '60px', color: '#9ca3af' }}>
            <Users size={48} style={{ marginBottom: '16px', color: 'rgba(255,255,255,0.1)' }} />
            <div>No staff members registered yet.</div>
            <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ marginTop: '16px', width: 'auto' }}>Add First Staff Member</button>
          </div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Conductor / Driver Name</th>
                <th>Email Address</th>
                <th>Mobile Number</th>
                <th>Role Designation</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {conductors.map(c => (
                <tr key={c.id}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontWeight: 'bold' }}>
                      <UserCheck size={16} color="#2563eb" />
                      {c.full_name}
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <Mail size={14} color="#9ca3af" />
                      {c.email}
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <Phone size={14} color="#9ca3af" />
                      <span style={{ fontFamily: 'monospace' }}>{c.phone_number}</span>
                    </div>
                  </td>
                  <td>
                    <span className="badge badge-success" style={{ textTransform: 'uppercase', fontSize: '10px' }}>
                      {c.role}
                    </span>
                  </td>
                  <td style={{ position: 'relative' }}>
                    <button
                      className="btn-action"
                      style={{
                        padding: '6px 10px',
                        borderRadius: '6px',
                        background: activeActionMenuId === c.id ? 'rgba(10,37,64,0.1)' : 'rgba(0,0,0,0.03)',
                        border: '1px solid rgba(0,0,0,0.08)',
                        color: 'var(--text-main)',
                        cursor: 'pointer',
                        display: 'inline-flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        transition: 'all 0.2s'
                      }}
                      onClick={() => setActiveActionMenuId(activeActionMenuId === c.id ? null : c.id)}
                    >
                      <Settings size={15} style={{ marginRight: '4px' }} /> Actions
                    </button>
                    
                    {activeActionMenuId === c.id && (
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
                              handleDeleteConductor(c.id);
                              setActiveActionMenuId(null);
                            }}
                            onMouseEnter={(e) => e.currentTarget.style.background = '#fef2f2'}
                            onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                          >
                            Remove Staff
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
        <div className="modal-backdrop" style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.5)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000 }}>
          <div className="table-card" style={{ width: '450px', background: '#0f172a', border: '1px solid rgba(255,255,255,0.1)', padding: '24px', borderRadius: '16px' }}>
            <h3 style={{ margin: '0 0 16px 0', fontSize: '18px', color: 'white' }}>Register Staff Conductor / Driver</h3>
            {error && <div style={{ color: '#ef4444', marginBottom: '12px', fontSize: '13px' }}>{error}</div>}
            
            <form onSubmit={handleAddConductor}>
              <div className="form-group">
                <label className="form-label">Full Name</label>
                <input type="text" className="form-input" placeholder="e.g. Sunil Perera" value={name} onChange={(e) => setName(e.target.value)} required />
              </div>
              
              <div className="form-group">
                <label className="form-label">Email Address</label>
                <input type="email" className="form-input" placeholder="e.g. sunil@lankaexpress.lk" value={email} onChange={(e) => setEmail(e.target.value)} required />
              </div>
              
              <div className="form-group">
                <label className="form-label">Mobile Number</label>
                <input type="text" className="form-input" placeholder="e.g. 0775556667" value={phone} onChange={(e) => setPhone(e.target.value)} required />
              </div>
              
              <div className="form-group">
                <label className="form-label">Console / Mobile Password</label>
                <input type="password" className="form-input" placeholder="Min 6 characters" value={password} onChange={(e) => setPassword(e.target.value)} required />
              </div>

              <div style={{ display: 'flex', gap: '12px', marginTop: '24px' }}>
                <button type="button" className="btn-secondary" onClick={() => setShowAddModal(false)} style={{ flex: 1, marginTop: 0, padding: '12px', fontSize: '14px' }}>Cancel</button>
                <button type="submit" className="btn-primary" disabled={submitting} style={{ flex: 1, marginTop: 0, padding: '12px', border: '1px solid transparent', fontSize: '14px' }}>
                  {submitting ? 'Registering...' : 'Register Staff'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
