import React, { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getCompanies, createCompany, toggleCompanyStatus, updateCompany, registerUser } from '../api/client';
import { Building2, Plus, Power, Settings, UserPlus, Edit3 } from 'lucide-react';

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
  const [editingCompany, setEditingCompany] = useState<Company | null>(null);
  const [registeringCompany, setRegisteringCompany] = useState<Company | null>(null);
  const [activeActionMenuId, setActiveActionMenuId] = useState<string | null>(null);
  
  // Create Form State
  const [form, setForm] = useState({ name: '', registration_number: '', contact_email: '', contact_phone: '', address: '' });
  
  // Edit Form State
  const [editForm, setEditForm] = useState({ name: '', registration_number: '', contact_email: '', contact_phone: '', address: '' });

  // Register Owner Form State
  const [ownerForm, setOwnerForm] = useState({ full_name: '', email: '', phone_number: '', password: '' });
  const [ownerError, setOwnerError] = useState('');
  const [ownerSuccess, setOwnerSuccess] = useState('');
  const [ownerSubmitting, setOwnerSubmitting] = useState(false);

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

  const handleUpdate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !editingCompany || !editForm.name) return;
    try {
      await updateCompany(token, editingCompany.id, editForm);
      setEditingCompany(null);
      await fetchCompanies();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to update company');
    }
  };

  const handleRegisterOwner = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !registeringCompany) return;
    setOwnerError('');
    setOwnerSuccess('');
    
    if (!ownerForm.full_name.trim()) return setOwnerError('Please enter full name');
    if (!ownerForm.email.trim()) return setOwnerError('Please enter email address');
    if (!ownerForm.password.trim() || ownerForm.password.length < 6) {
      return setOwnerError('Password must be at least 6 characters');
    }

    setOwnerSubmitting(true);
    try {
      await registerUser({
        email: ownerForm.email.trim(),
        password: ownerForm.password.trim(),
        full_name: ownerForm.full_name.trim(),
        phone_number: ownerForm.phone_number.trim() || null,
        role: 'owner',
        company_id: registeringCompany.id
      });
      setOwnerSuccess('Operator/Owner credentials registered successfully! They can now log in.');
      setOwnerForm({ full_name: '', email: '', phone_number: '', password: '' });
    } catch (err: any) {
      setOwnerError(err.message || 'Failed to register operator credentials');
    } finally {
      setOwnerSubmitting(false);
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
          <div className="stat-header"><span>Total Companies</span><Building2 size={18} style={{ color: '#2563eb' }} /></div>
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
                            minWidth: '170px',
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
                              borderBottom: '1px solid rgba(0,0,0,0.04)',
                              textAlign: 'left',
                              transition: 'background 0.15s',
                              color: 'var(--text-main)'
                            }}
                            onClick={() => {
                              setEditingCompany(c);
                              setEditForm({
                                name: c.name,
                                registration_number: c.registration_number || '',
                                contact_email: c.contact_email || '',
                                contact_phone: c.contact_phone || '',
                                address: c.address || ''
                              });
                              setActiveActionMenuId(null);
                            }}
                            onMouseEnter={(e) => e.currentTarget.style.background = '#f1f5f9'}
                            onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                          >
                            <Edit3 size={14} /> Edit Details
                          </div>
                          
                          <div
                            style={{
                              padding: '8px 12px',
                              cursor: 'pointer',
                              fontSize: '13px',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '8px',
                              borderBottom: '1px solid rgba(0,0,0,0.04)',
                              textAlign: 'left',
                              transition: 'background 0.15s',
                              color: 'var(--text-main)'
                            }}
                            onClick={() => {
                              setRegisteringCompany(c);
                              setOwnerForm({
                                full_name: '',
                                email: '',
                                phone_number: '',
                                password: ''
                              });
                              setOwnerError('');
                              setOwnerSuccess('');
                              setActiveActionMenuId(null);
                            }}
                            onMouseEnter={(e) => e.currentTarget.style.background = '#f1f5f9'}
                            onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                          >
                            <UserPlus size={14} /> Register Owner
                          </div>

                          <div
                            style={{
                              padding: '8px 12px',
                              cursor: 'pointer',
                              fontSize: '13px',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '8px',
                              color: c.is_active ? '#ef4444' : '#10b981',
                              textAlign: 'left',
                              transition: 'background 0.15s'
                            }}
                            onClick={() => {
                              handleToggle(c.id);
                              setActiveActionMenuId(null);
                            }}
                            onMouseEnter={(e) => e.currentTarget.style.background = c.is_active ? '#fef2f2' : '#ecfdf5'}
                            onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                          >
                            <Power size={14} /> {c.is_active ? 'Disable' : 'Enable'}
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
                <button type="submit" className="btn-primary" style={{ flex: 1, marginTop: 0, padding: '12px', border: '1px solid transparent', fontSize: '14px' }}>Register Company</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Company Modal */}
      {editingCompany && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)', display: 'flex',
          alignItems: 'center', justifyContent: 'center', zIndex: 1000,
        }}>
          <div style={{
            background: 'white', borderRadius: '16px', padding: '32px', width: '100%',
            maxWidth: '480px', boxShadow: '0 20px 60px rgba(0,0,0,0.15)',
            animation: 'fadeIn 0.3s ease-out',
          }}>
            <h3 style={{ marginBottom: '20px', fontSize: '18px', fontWeight: 700 }}>Edit Company Details</h3>
            <form onSubmit={handleUpdate}>
              <div className="form-group">
                <label className="form-label">Company Name *</label>
                <input className="form-input" value={editForm.name} onChange={e => setEditForm({ ...editForm, name: e.target.value })} required />
              </div>
              <div className="form-group">
                <label className="form-label">Business Registration No.</label>
                <input className="form-input" value={editForm.registration_number} onChange={e => setEditForm({ ...editForm, registration_number: e.target.value })} />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div className="form-group">
                  <label className="form-label">Email</label>
                  <input className="form-input" type="email" value={editForm.contact_email} onChange={e => setEditForm({ ...editForm, contact_email: e.target.value })} />
                </div>
                <div className="form-group">
                  <label className="form-label">Phone</label>
                  <input className="form-input" value={editForm.contact_phone} onChange={e => setEditForm({ ...editForm, contact_phone: e.target.value })} />
                </div>
              </div>
              <div className="form-group">
                <label className="form-label">Address</label>
                <input className="form-input" value={editForm.address} onChange={e => setEditForm({ ...editForm, address: e.target.value })} />
              </div>
              <div style={{ display: 'flex', gap: '12px', marginTop: '8px' }}>
                <button type="button" onClick={() => setEditingCompany(null)} style={{
                  flex: 1, padding: '12px', border: '1px solid rgba(0,0,0,0.1)', borderRadius: '10px',
                  background: 'white', cursor: 'pointer', fontSize: '14px', fontWeight: 600,
                }}>Cancel</button>
                <button type="submit" className="btn-primary" style={{ flex: 1, marginTop: 0, padding: '12px', border: '1px solid transparent', fontSize: '14px' }}>Save Changes</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Register Owner Modal */}
      {registeringCompany && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)', display: 'flex',
          alignItems: 'center', justifyContent: 'center', zIndex: 1000,
        }}>
          <div style={{
            background: 'white', borderRadius: '16px', padding: '32px', width: '100%',
            maxWidth: '480px', boxShadow: '0 20px 60px rgba(0,0,0,0.15)',
            animation: 'fadeIn 0.3s ease-out',
          }}>
            <h3 style={{ marginBottom: '8px', fontSize: '18px', fontWeight: 700 }}>Register Company Operator</h3>
            <p style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '20px' }}>
              Create owner credentials for <strong>{registeringCompany.name}</strong> to manage vehicles, routes, staff, and schedules.
            </p>

            {ownerError && (
              <div style={{
                background: 'rgba(239, 68, 68, 0.08)', border: '1px solid rgba(239, 68, 68, 0.2)',
                borderRadius: '8px', padding: '10px 14px', fontSize: '13px', color: '#ef4444', marginBottom: '16px'
              }}>
                {ownerError}
              </div>
            )}

            {ownerSuccess && (
              <div style={{
                background: 'rgba(16, 185, 129, 0.08)', border: '1px solid rgba(16, 185, 129, 0.2)',
                borderRadius: '8px', padding: '10px 14px', fontSize: '13px', color: '#10b981', marginBottom: '16px'
              }}>
                {ownerSuccess}
              </div>
            )}

            <form onSubmit={handleRegisterOwner}>
              <div className="form-group">
                <label className="form-label">Full Name *</label>
                <input className="form-input" placeholder="e.g. Sunil Shantha" value={ownerForm.full_name} onChange={e => setOwnerForm({ ...ownerForm, full_name: e.target.value })} required />
              </div>
              <div className="form-group">
                <label className="form-label">Operator Email *</label>
                <input className="form-input" type="email" placeholder="e.g. sunil@company.lk" value={ownerForm.email} onChange={e => setOwnerForm({ ...ownerForm, email: e.target.value })} required />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div className="form-group">
                  <label className="form-label">Contact Number</label>
                  <input className="form-input" placeholder="e.g. 0771234567" value={ownerForm.phone_number} onChange={e => setOwnerForm({ ...ownerForm, phone_number: e.target.value })} />
                </div>
                <div className="form-group">
                  <label className="form-label">Password *</label>
                  <input className="form-input" type="password" placeholder="Min 6 chars" value={ownerForm.password} onChange={e => setOwnerForm({ ...ownerForm, password: e.target.value })} required />
                </div>
              </div>
              <div style={{ display: 'flex', gap: '12px', marginTop: '16px' }}>
                <button type="button" onClick={() => setRegisteringCompany(null)} style={{
                  flex: 1, padding: '12px', border: '1px solid rgba(0,0,0,0.1)', borderRadius: '10px',
                  background: 'white', cursor: 'pointer', fontSize: '14px', fontWeight: 600,
                }}>Close</button>
                <button type="submit" className="btn-primary" disabled={ownerSubmitting} style={{ flex: 1, marginTop: 0, padding: '12px', border: '1px solid transparent', fontSize: '14px' }}>
                  {ownerSubmitting ? 'Registering...' : 'Register Operator'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
