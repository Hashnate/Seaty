import { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { getUsers } from '../api/client';
import { Users, Phone, Search, User, Calendar, Eye, Settings, FileText, Mail } from 'lucide-react';

interface PassengerRecord {
  id: string;
  full_name: string;
  email: string;
  phone_number?: string;
  nic_number?: string;
  gender?: string;
  created_at: string;
  updated_at: string;
}

// Helper to extract initials from name
const getInitials = (name: string) => {
  if (!name) return 'P';
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return name.trim().substring(0, 2).toUpperCase();
};

export default function PassengersPage() {
  const { token } = useAuth();
  const [passengers, setPassengers] = useState<PassengerRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedPassenger, setSelectedPassenger] = useState<PassengerRecord | null>(null);
  const [activeActionMenuId, setActiveActionMenuId] = useState<string | null>(null);

  const fetchPassengers = () => {
    if (!token) return;
    setLoading(true);
    getUsers(token, 'passenger')
      .then(data => setPassengers((data as PassengerRecord[]) || []))
      .catch(() => setPassengers([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchPassengers();
  }, [token]);

  const filteredPassengers = passengers.filter(p => {
    const query = searchQuery.toLowerCase().trim();
    if (!query) return true;
    return (
      p.full_name?.toLowerCase().includes(query) ||
      p.phone_number?.toLowerCase().includes(query) ||
      p.nic_number?.toLowerCase().includes(query)
    );
  });

  return (
    <div>
      {/* Header */}
      <div className="page-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
        <div>
          <h1 className="page-title">Registered Passengers</h1>
          <p className="page-subtitle">View and inspect customer accounts registered on the mobile booking application.</p>
        </div>
        
        {/* Styled Single Count Pill Badge Option */}
        <div 
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '10px',
            background: 'linear-gradient(135deg, rgba(37, 99, 235, 0.08) 0%, rgba(37, 99, 235, 0.03) 100%)',
            border: '1px solid rgba(37, 99, 235, 0.18)',
            padding: '8px 18px',
            borderRadius: '20px',
            color: 'var(--color-primary)',
            fontWeight: 700,
            fontSize: '13.5px',
            boxShadow: '0 4px 12px rgba(37, 99, 235, 0.05)',
            transition: 'all 0.3s ease',
            cursor: 'default',
            userSelect: 'none'
          }}
          onMouseEnter={e => {
            e.currentTarget.style.transform = 'translateY(-1px)';
            e.currentTarget.style.boxShadow = '0 6px 16px rgba(37, 99, 235, 0.08)';
            e.currentTarget.style.borderColor = 'rgba(37, 99, 235, 0.3)';
          }}
          onMouseLeave={e => {
            e.currentTarget.style.transform = 'translateY(0)';
            e.currentTarget.style.boxShadow = '0 4px 12px rgba(37, 99, 235, 0.05)';
            e.currentTarget.style.borderColor = 'rgba(37, 99, 235, 0.18)';
          }}
        >
          <Users size={16} style={{ strokeWidth: 2.5 }} />
          <span>Total Passengers: <strong style={{ fontSize: '15px', marginLeft: '2px', color: 'var(--color-primary)' }}>{passengers.length}</strong></span>
        </div>
      </div>

      {/* Controls: Search */}
      <div className="table-card" style={{ padding: '16px', marginBottom: '20px' }}>
        <div style={{ position: 'relative', width: '100%', maxWidth: '380px' }}>
          <Search size={16} style={{ position: 'absolute', left: '12px', top: '13px', color: 'var(--text-muted)' }} />
          <input
            type="text"
            className="form-input"
            placeholder="Search by name or mobile..."
            style={{ paddingLeft: '38px', margin: 0 }}
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
          />
        </div>
      </div>

      {/* Passenger Table */}
      <div className="table-card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>Loading passengers...</div>
        ) : filteredPassengers.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '60px', color: 'var(--text-muted)' }}>
            <Users size={48} style={{ marginBottom: '16px', opacity: 0.2 }} />
            <div>{searchQuery ? 'No matching passengers found.' : 'No passengers registered yet.'}</div>
          </div>
        ) : (
          <table className="custom-table">
            <thead>
              <tr>
                <th>Passenger Name</th>
                <th>Mobile Number</th>
                <th>NIC Number</th>
                <th>Joined Date</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredPassengers.map(p => (
                <tr key={p.id}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px', fontWeight: 'bold' }}>
                      <div style={{
                        width: '32px',
                        height: '32px',
                        borderRadius: '50%',
                        background: 'linear-gradient(135deg, rgba(37, 99, 235, 0.08) 0%, rgba(37, 99, 235, 0.03) 100%)',
                        color: 'var(--color-primary)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        fontSize: '12px',
                        fontWeight: 700,
                        border: '1px solid rgba(37, 99, 235, 0.15)',
                        flexShrink: 0
                      }}>
                        {getInitials(p.full_name)}
                      </div>
                      <span style={{ color: 'var(--text-dark)' }}>{p.full_name}</span>
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <Phone size={14} color="var(--text-muted)" />
                      <span style={{ fontFamily: 'monospace' }}>{p.phone_number || '—'}</span>
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <FileText size={14} color="var(--text-muted)" />
                      <span>{p.nic_number || '—'}</span>
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <Calendar size={14} color="var(--text-muted)" />
                      <span>{new Date(p.created_at).toLocaleDateString('en-LK', { dateStyle: 'medium' })}</span>
                    </div>
                  </td>
                  <td style={{ position: 'relative' }}>
                    <button
                      className="btn-action"
                      style={{
                        padding: '6px 10px',
                        borderRadius: '6px',
                        background: activeActionMenuId === p.id ? 'rgba(10,37,64,0.1)' : 'rgba(0,0,0,0.03)',
                        border: '1px solid rgba(0,0,0,0.08)',
                        color: 'var(--text-dark)',
                        cursor: 'pointer',
                        display: 'inline-flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        transition: 'all 0.2s'
                      }}
                      onClick={() => setActiveActionMenuId(activeActionMenuId === p.id ? null : p.id)}
                    >
                      <Settings size={15} style={{ marginRight: '4px' }} /> Actions
                    </button>
                    
                    {activeActionMenuId === p.id && (
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
                            minWidth: '140px',
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
                              color: 'var(--text-dark)',
                              textAlign: 'left',
                              transition: 'background 0.15s'
                            }}
                            onClick={() => {
                              setSelectedPassenger(p);
                              setActiveActionMenuId(null);
                            }}
                            onMouseEnter={(e) => e.currentTarget.style.background = 'var(--bg-secondary)'}
                            onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
                          >
                            <Eye size={14} color="var(--color-primary)" />
                            View Details
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

      {/* Detail Inspector Modal */}
      {selectedPassenger && (
        <div className="modal-backdrop" style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(15, 23, 42, 0.4)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000, backdropFilter: 'blur(8px)' }}>
          <div className="table-card" style={{ width: '460px', background: '#ffffff', border: '1px solid var(--border-color)', padding: '28px', borderRadius: '16px', boxShadow: '0 24px 48px -12px rgba(10, 37, 64, 0.18)' }}>
            
            {/* Modal Profile Header */}
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: '24px', borderBottom: '1px solid var(--border-color)', paddingBottom: '18px' }}>
              <div style={{
                width: '64px',
                height: '64px',
                borderRadius: '50%',
                background: 'linear-gradient(135deg, rgba(37, 99, 235, 0.12) 0%, rgba(37, 99, 235, 0.06) 100%)',
                color: 'var(--color-primary)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '22px',
                fontWeight: 800,
                border: '2px solid rgba(37, 99, 235, 0.2)',
                marginBottom: '12px',
                boxShadow: '0 4px 12px rgba(37, 99, 235, 0.08)'
              }}>
                {getInitials(selectedPassenger.full_name)}
              </div>
              <h3 style={{ margin: 0, fontSize: '18px', color: 'var(--text-dark)', fontWeight: 700 }}>{selectedPassenger.full_name}</h3>
              <span style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px', fontWeight: 500 }}>Passenger Account</span>
            </div>

            {/* Modal Body Data Fields */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              
              {/* Conditional Email Address */}
              {selectedPassenger.email && !selectedPassenger.email.endsWith('@seaty.lk') && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <div style={{ padding: '8px', borderRadius: '10px', background: 'var(--bg-secondary)', color: 'var(--text-muted)', display: 'flex' }}>
                    <Mail size={15} />
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontSize: '10px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>Email Address</span>
                    <span style={{ fontSize: '14px', color: 'var(--text-dark)', fontWeight: 500 }}>{selectedPassenger.email}</span>
                  </div>
                </div>
              )}

              {/* Mobile Number */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <div style={{ padding: '8px', borderRadius: '10px', background: 'var(--bg-secondary)', color: 'var(--text-muted)', display: 'flex' }}>
                  <Phone size={15} />
                </div>
                <div style={{ display: 'flex', flexDirection: 'column' }}>
                  <span style={{ fontSize: '10px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>Mobile Number</span>
                  <span style={{ fontSize: '14px', color: 'var(--text-dark)', fontWeight: 500, fontFamily: 'monospace' }}>{selectedPassenger.phone_number || '—'}</span>
                </div>
              </div>

              {/* Grid: NIC & Gender */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', borderTop: '1px solid var(--border-color)', paddingTop: '16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <div style={{ padding: '8px', borderRadius: '10px', background: 'var(--bg-secondary)', color: 'var(--text-muted)', display: 'flex' }}>
                    <FileText size={15} />
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontSize: '10px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>NIC Number</span>
                    <span style={{ fontSize: '14px', color: 'var(--text-dark)', fontWeight: 500 }}>{selectedPassenger.nic_number || '—'}</span>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <div style={{ padding: '8px', borderRadius: '10px', background: 'var(--bg-secondary)', color: 'var(--text-muted)', display: 'flex' }}>
                    <User size={15} />
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontSize: '10px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>Gender</span>
                    <span style={{ fontSize: '14px', color: 'var(--text-dark)', fontWeight: 500, textTransform: 'capitalize' }}>{selectedPassenger.gender || '—'}</span>
                  </div>
                </div>
              </div>

              {/* Grid: Registration Metadata */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', borderTop: '1px solid var(--border-color)', paddingTop: '16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <div style={{ padding: '8px', borderRadius: '10px', background: 'var(--bg-secondary)', color: 'var(--text-muted)', display: 'flex' }}>
                    <Calendar size={15} />
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontSize: '10px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>Joined On</span>
                    <span style={{ fontSize: '13px', color: 'var(--text-dark)', fontWeight: 500 }}>
                      {new Date(selectedPassenger.created_at).toLocaleDateString('en-LK', { dateStyle: 'medium' })}
                    </span>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <div style={{ padding: '8px', borderRadius: '10px', background: 'var(--bg-secondary)', color: 'var(--text-muted)', display: 'flex' }}>
                    <Calendar size={15} />
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontSize: '10px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600 }}>Last Active</span>
                    <span style={{ fontSize: '13px', color: 'var(--text-dark)', fontWeight: 500 }}>
                      {new Date(selectedPassenger.updated_at).toLocaleDateString('en-LK', { dateStyle: 'medium' })}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Action Buttons */}
            <div style={{ display: 'flex', marginTop: '28px' }}>
              <button 
                type="button" 
                className="btn-secondary" 
                onClick={() => setSelectedPassenger(null)} 
                style={{ flex: 1, marginTop: 0, padding: '12px', background: 'transparent', border: '1px solid var(--border-color)', color: 'var(--text-muted)', fontSize: '14px', borderRadius: '10px', fontWeight: 600 }}
              >
                Close Details
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}