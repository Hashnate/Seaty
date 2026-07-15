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
  const { logout, user } = useAuth();

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const userRole = (user as { role?: string })?.role || 'admin';

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
        <div className="sidebar-brand">
          <img src="/app_logo.png" alt="Seaty Logo" style={{ height: '28px', objectFit: 'contain' }} />
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
        <div className="sidebar-footer">
          <div className="sidebar-item" onClick={handleLogout} style={{ color: '#ef4444' }}>
            <LogOut size={18} />
            Sign Out
          </div>
        </div>
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
          </div>
        </header>
        <div style={{ flexGrow: 1 }}>
          {children}
        </div>
      </main>
    </div>
  );
}
