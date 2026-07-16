import React from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import NotificationDrawer from './NotificationDrawer';
import {
  Activity,
  CheckCircle,
  Building2,
  Users,
  Map as MapIcon,
  Settings as SettingsIcon,
  Route as RouteIcon,
  LogOut,
  Bus,
  Calendar,
  Contact,
  ChevronDown,
  Key,
} from 'lucide-react';

const NAV_ITEMS = [
  { path: '/', icon: Activity, label: 'Overview & Stats' },
  { path: '/approvals', icon: CheckCircle, label: 'Pending Approvals' },
  { path: '/companies', icon: Building2, label: 'Bus Companies' },
  { path: '/routes', icon: RouteIcon, label: 'Route Templates' },
  { path: '/fleet', icon: Bus, label: 'My Fleet' },
  { path: '/trips', icon: Calendar, label: 'Trip Scheduling' },
  { path: '/conductors', icon: Contact, label: 'My Conductors' },
  { path: '/map', icon: MapIcon, label: 'Live Fleet Map', badge: 'Live' },
  { path: '/bookings', icon: Users, label: 'Bookings Log' },
  { path: '/settings', icon: SettingsIcon, label: 'Console Settings' },
];

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const location = useLocation();
  const { logout, user, token } = useAuth();

  const [isProfileOpen, setIsProfileOpen] = React.useState(false);
  const [isPasswordModalOpen, setIsPasswordModalOpen] = React.useState(false);
  const [currentPassword, setCurrentPassword] = React.useState('');
  const [newPassword, setNewPassword] = React.useState('');
  const [confirmPassword, setConfirmPassword] = React.useState('');
  const [isSubmittingPassword, setIsSubmittingPassword] = React.useState(false);
  const [passwordError, setPasswordError] = React.useState<string | null>(null);
  const [passwordSuccess, setPasswordSuccess] = React.useState<string | null>(null);

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordError(null);
    setPasswordSuccess(null);

    if (newPassword.length < 6) {
      setPasswordError('New password must be at least 6 characters long.');
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordError('New passwords do not match.');
      return;
    }

    setIsSubmittingPassword(true);
    try {
      const { changePassword } = await import('../api/client');
      if (!token) throw new Error('Not authenticated.');
      await changePassword(token, {
        current_password: currentPassword,
        new_password: newPassword
      });
      setPasswordSuccess('Password updated successfully!');
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      setTimeout(() => {
        setIsPasswordModalOpen(false);
        setPasswordSuccess(null);
      }, 1500);
    } catch (err) {
      setPasswordError(err instanceof Error ? err.message : 'Failed to change password.');
    } finally {
      setIsSubmittingPassword(false);
    }
  };

  const typedUser = user as { full_name?: string; email?: string; role?: string } | null;
  const userRole = typedUser?.role || 'admin';

  const visibleNavItems = NAV_ITEMS.filter(item => {
    if (userRole === 'owner') {
      return ['/', '/fleet', '/trips', '/conductors', '/bookings', '/map'].includes(item.path);
    }
    // Admins can see all views
    return ['/', '/approvals', '/companies', '/routes', '/fleet', '/trips', '/conductors', '/map', '/bookings', '/settings'].includes(item.path);
  });

  return (
    <div className="dashboard-layout">
      <aside className="sidebar">
        <div className="sidebar-brand" style={{ display: 'flex', alignItems: 'center', gap: '10px', padding: '16px' }}>
          <img src="/app_logo.png" alt="Seaty Logo" style={{ height: '28px', objectFit: 'contain' }} />
          <span style={{ fontSize: '16px', fontWeight: 700, color: 'var(--text-dark)' }}>Seaty Admin Console</span>
        </div>
        <ul className="sidebar-menu">
          {visibleNavItems.map(item => {
            const isActive = location.pathname === item.path;
            return (
              <li
                key={item.path}
                className={`sidebar-item ${isActive ? 'active' : ''}`}
                onClick={() => navigate(item.path)}
              >
                <item.icon size={18} />
                {item.label}
                {item.badge && (
                  <span className="badge badge-success" style={{ marginLeft: 'auto', padding: '2px 6px', fontSize: '10px' }}>
                    {item.badge}
                  </span>
                )}
              </li>
            );
          })}
        </ul>
      </aside>
      <main className="main-content" style={{ display: 'flex', flexDirection: 'column' }}>
        <header className="admin-navbar" style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: '12px 24px',
          background: 'var(--bg-card)',
          borderBottom: '1px solid var(--border-color)',
          borderRadius: '12px',
          marginBottom: '24px',
          boxShadow: '0 2px 10px rgba(0,0,0,0.02)'
        }}>
          <div className="navbar-left">
            <span style={{ fontSize: '14px', color: 'var(--text-muted)' }}>Console Control / </span>
            <span style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-dark)' }}>
              {location.pathname === '/' ? 'Dashboard Overview' : visibleNavItems.find(item => item.path === location.pathname)?.label || 'Console'}
            </span>
          </div>

          <div className="navbar-right" style={{ display: 'flex', alignItems: 'center', gap: '20px' }}>
            <NotificationDrawer />
            <div className="profile-menu-container" style={{ position: 'relative' }}>
              <button 
                onClick={() => setIsProfileOpen(!isProfileOpen)} 
                className="profile-btn" 
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  background: 'none', 
                  border: 'none', 
                  cursor: 'pointer',
                  color: 'var(--text-dark)',
                  padding: '4px 8px',
                  borderRadius: '8px',
                  transition: 'background 0.2s',
                }}
                onMouseEnter={(e) => e.currentTarget.style.background = 'rgba(0,0,0,0.03)'}
                onMouseLeave={(e) => e.currentTarget.style.background = 'none'}
              >
                <div style={{
                  width: '32px',
                  height: '32px',
                  borderRadius: '50%',
                  background: 'var(--color-primary-light, #fff0e6)',
                  color: 'var(--color-primary, #e65100)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 'bold',
                  fontSize: '14px',
                  border: '1px solid var(--border-color)'
                }}>
                  {typedUser?.full_name ? String(typedUser.full_name).charAt(0).toUpperCase() : 'A'}
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', textAlign: 'left' }}>
                  <span style={{ fontSize: '12px', fontWeight: 600 }}>{typedUser?.full_name || 'Admin User'}</span>
                  <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>{String(typedUser?.role || 'admin').toUpperCase()}</span>
                </div>
                <ChevronDown size={14} style={{ opacity: 0.7 }} />
              </button>

              {isProfileOpen && (
                <>
                  <div 
                    onClick={() => setIsProfileOpen(false)} 
                    style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, zIndex: 998 }} 
                  />
                  <div className="profile-dropdown" style={{
                    position: 'absolute',
                    right: 0,
                    top: '100%',
                    marginTop: '8px',
                    width: '240px',
                    background: 'var(--bg-card, #ffffff)',
                    border: '1px solid var(--border-color)',
                    borderRadius: '12px',
                    boxShadow: '0 4px 20px rgba(0,0,0,0.08)',
                    zIndex: 999,
                    overflow: 'hidden'
                  }}>
                    <div style={{ padding: '16px', borderBottom: '1px solid var(--border-color)', background: 'rgba(0,0,0,0.01)' }}>
                      <strong style={{ display: 'block', fontSize: '14px' }}>{typedUser?.full_name}</strong>
                      <span style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', wordBreak: 'break-all', marginTop: '2px' }}>{typedUser?.email}</span>
                      <span style={{ 
                        display: 'inline-block', 
                        fontSize: '9px', 
                        fontWeight: 'bold', 
                        background: 'var(--color-primary-light, #fff0e6)', 
                        color: 'var(--color-primary, #e65100)',
                        padding: '2px 6px',
                        borderRadius: '4px',
                        marginTop: '6px',
                        textTransform: 'uppercase'
                      }}>{typedUser?.role}</span>
                    </div>
                    <ul style={{ listStyle: 'none', padding: '6px 0', margin: 0 }}>
                      <li 
                        onClick={() => {
                          setIsProfileOpen(false);
                          setIsPasswordModalOpen(true);
                        }}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: '10px',
                          padding: '10px 16px',
                          fontSize: '13px',
                          cursor: 'pointer',
                          transition: 'background 0.2s',
                        }}
                        onMouseEnter={(e) => e.currentTarget.style.backgroundColor = 'rgba(0,0,0,0.03)'}
                        onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
                      >
                        <Key size={16} style={{ color: 'var(--color-primary)' }} />
                        Change Password
                      </li>
                      <li 
                        onClick={handleLogout}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: '10px',
                          padding: '10px 16px',
                          fontSize: '13px',
                          cursor: 'pointer',
                          color: '#ef4444',
                          borderTop: '1px solid var(--border-color)',
                          transition: 'background 0.2s',
                        }}
                        onMouseEnter={(e) => e.currentTarget.style.backgroundColor = 'rgba(239, 68, 68, 0.05)'}
                        onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
                      >
                        <LogOut size={16} />
                        Sign Out
                      </li>
                    </ul>
                  </div>
                </>
              )}
            </div>
          </div>
        </header>
        <div style={{ flexGrow: 1 }}>
          {children}
        </div>
      </main>

      {isPasswordModalOpen && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(0, 0, 0, 0.4)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 10000,
          backdropFilter: 'blur(2px)'
        }}>
          <div style={{
            background: 'var(--bg-card, #ffffff)',
            width: '400px',
            borderRadius: '16px',
            boxShadow: '0 10px 25px rgba(0,0,0,0.15)',
            border: '1px solid var(--border-color)',
            overflow: 'hidden'
          }}>
            <div style={{
              padding: '16px 20px',
              borderBottom: '1px solid var(--border-color)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center'
            }}>
              <h3 style={{ margin: 0, fontSize: '16px', fontWeight: 600 }}>Change Password</h3>
              <button 
                onClick={() => {
                  setIsPasswordModalOpen(false);
                  setPasswordError(null);
                  setPasswordSuccess(null);
                  setCurrentPassword('');
                  setNewPassword('');
                  setConfirmPassword('');
                }}
                style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '18px', opacity: 0.5 }}
              >
                &times;
              </button>
            </div>
            <form onSubmit={handleChangePassword} style={{ padding: '20px' }}>
              {passwordError && (
                <div style={{
                  background: '#fef2f2',
                  border: '1px solid #fca5a5',
                  color: '#b91c1c',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  fontSize: '12px',
                  marginBottom: '16px'
                }}>
                  {passwordError}
                </div>
              )}
              {passwordSuccess && (
                <div style={{
                  background: '#f0fdf4',
                  border: '1px solid #86efac',
                  color: '#15803d',
                  padding: '8px 12px',
                  borderRadius: '8px',
                  fontSize: '12px',
                  marginBottom: '16px'
                }}>
                  {passwordSuccess}
                </div>
              )}
              <div style={{ marginBottom: '14px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '6px', color: 'var(--text-dark)' }}>
                  Current Password
                </label>
                <input
                  type="password"
                  className="form-input"
                  style={{ width: '100%' }}
                  value={currentPassword}
                  onChange={(e) => setCurrentPassword(e.target.value)}
                  required
                />
              </div>
              <div style={{ marginBottom: '14px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '6px', color: 'var(--text-dark)' }}>
                  New Password
                </label>
                <input
                  type="password"
                  className="form-input"
                  style={{ width: '100%' }}
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  required
                />
              </div>
              <div style={{ marginBottom: '20px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '6px', color: 'var(--text-dark)' }}>
                  Confirm New Password
                </label>
                <input
                  type="password"
                  className="form-input"
                  style={{ width: '100%' }}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  required
                />
              </div>
              <div style={{ display: 'flex', gap: '10px', justifyContent: 'flex-end' }}>
                <button
                  type="button"
                  onClick={() => {
                    setIsPasswordModalOpen(false);
                    setPasswordError(null);
                    setPasswordSuccess(null);
                    setCurrentPassword('');
                    setNewPassword('');
                    setConfirmPassword('');
                  }}
                  style={{
                    padding: '8px 16px',
                    background: 'none',
                    border: '1px solid var(--border-color)',
                    borderRadius: '8px',
                    cursor: 'pointer',
                    fontSize: '13px',
                    fontWeight: 600,
                  }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmittingPassword}
                  style={{
                    padding: '8px 16px',
                    background: 'var(--color-primary, #e65100)',
                    color: 'white',
                    border: 'none',
                    borderRadius: '8px',
                    cursor: 'pointer',
                    fontSize: '13px',
                    fontWeight: 600,
                  }}
                >
                  {isSubmittingPassword ? 'Saving...' : 'Update Password'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
