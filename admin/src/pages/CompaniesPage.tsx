import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getCompanies, createCompany, toggleCompanyStatus } from '../api/client';
import { Building2, Plus, Power } from 'lucide-react';

interface Company {
  id: string;
  name: string;
  registration_number: string | null;
  contact_email: string | null;
  contact_phone: string | null;
  address: string | null;
  is_active: boolean;
  created_at: string;
}

export default function CompaniesPage() {
  const { token } = useAuth();
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [form, setForm] = useState({ name: '', registration_number: '', contact_email: '', contact_phone: '', address: '' });

  const fetchCompanies = async () => {
    if (!token) return;
    setLoading(true);
    try {
      const data = await getCompanies(token) as Company[];
      setCompanies(data);
    } catch {
      setCompanies([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchCompanies(); }, [token]);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !form.name) return;
    try {
      await createCompany(token, form);
      setShowModal(false);
      setForm({ name: '', registration_number: '', contact_email: '', contact_phone: '', address: '' });
      await fetchCompanies();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to create company');
    }
  };

  const handleToggle = async (id: string) => {
    if (!token) return;
    try {
      await toggleCompanyStatus(token, id);
      await fetchCompanies();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to toggle status');
    }
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h1 className="page-title">Bus Companies</h1>
          <p className="page-subtitle">Register and manage transport operator companies across Sri Lanka.</p>
        </div>
        <button className="btn-primary" style={{ width: 'auto', padding: '10px 20px', display: 'flex', alignItems: 'center', gap: '8px' }} onClick={() => setShowModal(true)}>
          <Plus size={16} /> Add Company
        </button>
      </div>

      <div className="stats-grid" style={{ marginBottom: '24px' }}>
        <div className="stat-card">
          <div className="stat-header"><span>Total Companies</span><Building2 size={18} style={{ color: '#e65100' }} /></div>
          <div className="stat-value">{companies.length}</div>
        </div>
        <div className="stat-card">
          <div className="stat-header"><span>Active</span><Power size={18} style={{ color: '#10b981' }} /></div>
          <div className="stat-value">{companies.filter(c => c.is_active).length}</div>
        </div>
        <div className="stat-card">
          <div className="stat-header"><span>Disabled</span><Power size={18} style={{ color: '#ef4444' }} /></div>
          <div className="stat-value">{companies.filter(c => !c.is_active).length}</div>
        </div>
      </div>

      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>Loading companies...</div>
        ) : companies.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '40px', color: '#9ca3af' }}>
            <Building2 size={48} style={{ color: '#9ca3af', marginBottom: '16px' }} />
            <h4>No companies registered yet</h4>
            <p style={{ fontSize: '13px', marginTop: '4px' }}>Click "Add Company" to register your first bus operator.</p>
          </div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Company Name</th>
                <th>Registration</th>
                <th>Contact</th>
                <th>Address</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {companies.map(c => (
                <tr key={c.id}>
                  <td><strong>{c.name}</strong></td>
                  <td>{c.registration_number || '—'}</td>
                  <td>
                    <div>{c.contact_email || '—'}</div>
                    <div style={{ fontSize: '11px', color: '#9ca3af' }}>{c.contact_phone || ''}</div>
                  </td>
                  <td style={{ maxWidth: '200px' }}>{c.address || '—'}</td>
                  <td>
                    <span className={`badge ${c.is_active ? 'badge-success' : 'badge-danger'}`}>
                      {c.is_active ? 'Active' : 'Disabled'}
                    </span>
                  </td>
                  <td>
                    <button
                      className={`btn-action ${c.is_active ? 'btn-action-danger' : 'btn-action-success'}`}
                      onClick={() => handleToggle(c.id)}
                    >
                      {c.is_active ? 'Disable' : 'Enable'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Add Company Modal */}
      {showModal && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)', display: 'flex',
          alignItems: 'center', justifyContent: 'center', zIndex: 1000,
        }}>
          <div style={{
            background: 'white', borderRadius: '16px', padding: '32px', width: '100%',
            maxWidth: '480px', boxShadow: '0 20px 60px rgba(0,0,0,0.15)',
            animation: 'fadeIn 0.3s ease-out',
          }}>
            <h3 style={{ marginBottom: '20px', fontSize: '18px', fontWeight: 700 }}>Register New Bus Company</h3>
            <form onSubmit={handleCreate}>
              <div className="form-group">
                <label className="form-label">Company Name *</label>
                <input className="form-input" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} required />
              </div>
              <div className="form-group">
                <label className="form-label">Business Registration No.</label>
                <input className="form-input" value={form.registration_number} onChange={e => setForm({ ...form, registration_number: e.target.value })} />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div className="form-group">
                  <label className="form-label">Email</label>
                  <input className="form-input" type="email" value={form.contact_email} onChange={e => setForm({ ...form, contact_email: e.target.value })} />
                </div>
                <div className="form-group">
                  <label className="form-label">Phone</label>
                  <input className="form-input" value={form.contact_phone} onChange={e => setForm({ ...form, contact_phone: e.target.value })} />
                </div>
              </div>
              <div className="form-group">
                <label className="form-label">Address</label>
                <input className="form-input" value={form.address} onChange={e => setForm({ ...form, address: e.target.value })} />
              </div>
              <div style={{ display: 'flex', gap: '12px', marginTop: '8px' }}>
                <button type="button" onClick={() => setShowModal(false)} style={{
                  flex: 1, padding: '12px', border: '1px solid rgba(0,0,0,0.1)', borderRadius: '10px',
                  background: 'white', cursor: 'pointer', fontSize: '14px', fontWeight: 600,
                }}>Cancel</button>
                <button type="submit" className="btn-primary" style={{ flex: 1 }}>Register Company</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
