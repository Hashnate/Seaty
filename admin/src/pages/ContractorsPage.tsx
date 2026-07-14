import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getContractors, createContractor, deleteContractor } from '../api/client';
import { Plus, Trash2, Users, Mail, Phone, UserCheck } from 'lucide-react';

interface ContractorRecord {
  id: string;
  full_name: string;
  email: string;
  phone_number: string;
  role: string;
}

export default function ContractorsPage() {
  const { token } = useAuth();
  const [contractors, setContractors] = useState<ContractorRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  
  // Form State
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const fetchContractors = () => {
    if (!token) return;
    setLoading(true);
    getContractors(token)
      .then(data => setContractors((data as ContractorRecord[]) || []))
      .catch(() => setContractors([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchContractors();
  }, [token]);

  const handleAddContractor = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    
    if (!name.trim()) return setError('Please enter staff name');
    if (!email.trim()) return setError('Please enter staff email');
    if (!phone.trim()) return setError('Please enter staff phone number');
    if (!password.trim() || password.length < 6) return setError('Password must be at least 6 characters');
    
    setSubmitting(true);

    try {
      await createContractor(token, {
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
      fetchContractors();
    } catch (err: any) {
      setError(err.message || 'Failed to add staff member');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteContractor = async (id: string) => {
    if (!token || !window.confirm('Are you sure you want to remove this staff member from your company?')) return;
    try {
      await deleteContractor(token, id);
      fetchContractors();
    } catch (err: any) {
      alert(err.message || 'Failed to delete staff member');
    }
  };

  return (
    <div>
      <div className="page-header" style={{ display: 'flex', justifyContent: 'between', alignItems: 'center' }}>
        <div>
          <h1 className="page-title">Company Contractors & Staff</h1>
          <p className="page-subtitle">Add and manage drivers, conductors, and checkers authorized to log in to mobile services.</p>
        </div>
        <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 18px' }}>
          <Plus size={16} /> Add Conductor / Driver
        </button>
      </div>

      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading staff...</div>
        ) : contractors.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '60px', color: '#9ca3af' }}>
            <Users size={48} style={{ marginBottom: '16px', color: 'rgba(255,255,255,0.1)' }} />
            <div>No staff members registered yet.</div>
            <button className="btn-primary" onClick={() => setShowAddModal(true)} style={{ marginTop: '16px' }}>Add First Staff Member</button>
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
              {contractors.map(c => (
                <tr key={c.id}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontWeight: 'bold' }}>
                      <UserCheck size={16} color="#e65100" />
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
                  <td>
                    <button onClick={() => handleDeleteContractor(c.id)} className="btn-danger" style={{ padding: '6px 12px', background: 'transparent', border: 'none', color: '#ef4444' }}>
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
            <h3 style={{ margin: '0 0 16px 0', fontSize: '18px', color: 'white' }}>Register Staff Conductor / Driver</h3>
            {error && <div style={{ color: '#ef4444', marginBottom: '12px', fontSize: '13px' }}>{error}</div>}
            
            <form onSubmit={handleAddContractor}>
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

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '24px' }}>
                <button type="button" className="btn-secondary" onClick={() => setShowAddModal(false)} style={{ padding: '8px 16px' }}>Cancel</button>
                <button type="submit" className="btn-primary" disabled={submitting} style={{ padding: '8px 20px' }}>
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
