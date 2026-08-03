import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './hooks/useAuth';
import LoginPage from './pages/LoginPage';
import DashboardLayout from './components/DashboardLayout';
import OverviewPage from './pages/OverviewPage';
import ApprovalsPage from './pages/ApprovalsPage';
import CompaniesPage from './pages/CompaniesPage';
import BookingsPage from './pages/BookingsPage';
import LiveMapPage from './pages/LiveMapPage';
import SettingsPage from './pages/SettingsPage';
import RoutesPage from './pages/RoutesPage';
import MyFleetPage from './pages/MyFleetPage';
import MyTripsPage from './pages/MyTripsPage';
import ConductorsPage from './pages/ConductorsPage';
import PassengersPage from './pages/PassengersPage';
import NotificationsPage from './pages/NotificationsPage';

import { Loader2 } from 'lucide-react';

function LoadingScreen() {
  return (
    <div style={{
      minHeight: '100vh',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: 'var(--bg-secondary)',
      fontFamily: 'var(--font-family)',
    }}>
      <div style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: '16px',
        padding: '24px 36px',
        background: 'var(--bg-card)',
        borderRadius: '16px',
        boxShadow: 'var(--shadow-card)',
        border: '1px solid var(--border-color)',
      }}>
        <Loader2 
          className="animate-spin" 
          size={36} 
          style={{ color: 'var(--color-primary)' }} 
        />
        <p style={{
          fontSize: '14.5px',
          fontWeight: 600,
          color: 'var(--text-main)',
          margin: 0,
        }}>
          Loading details...
        </p>
      </div>
    </div>
  );
}

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { token, user, isLoading } = useAuth();
  
  if (!token) return <Navigate to="/login" replace />;
  if (isLoading || !user) return <LoadingScreen />;
  
  return <>{children}</>;
}

function RoleProtectedRoute({ allowed, children }: { allowed: string[]; children: React.ReactNode }) {
  const { user } = useAuth();
  const userRole = (user as { role?: string })?.role || 'passenger';
  
  if (!allowed.includes(userRole)) {
    return <Navigate to="/" replace />;
  }
  return <>{children}</>;
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route
            path="/*"
            element={
              <ProtectedRoute>
                <DashboardLayout>
                  <Routes>
                    <Route path="/" element={<OverviewPage />} />
                    <Route 
                      path="/approvals" 
                      element={
                        <RoleProtectedRoute allowed={['admin']}>
                          <ApprovalsPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/companies" 
                      element={
                        <RoleProtectedRoute allowed={['admin']}>
                          <CompaniesPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/routes" 
                      element={
                        <RoleProtectedRoute allowed={['admin']}>
                          <RoutesPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route path="/bookings" element={<BookingsPage />} />
                    <Route path="/map" element={<LiveMapPage />} />
                    <Route 
                      path="/fleet" 
                      element={
                        <RoleProtectedRoute allowed={['owner', 'admin']}>
                          <MyFleetPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/trips" 
                      element={
                        <RoleProtectedRoute allowed={['owner', 'admin']}>
                          <MyTripsPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/conductors" 
                      element={
                        <RoleProtectedRoute allowed={['owner', 'admin']}>
                          <ConductorsPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/passengers" 
                      element={
                        <RoleProtectedRoute allowed={['admin']}>
                          <PassengersPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/settings" 
                      element={
                        <RoleProtectedRoute allowed={['admin']}>
                          <SettingsPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/notifications" 
                      element={
                        <RoleProtectedRoute allowed={['admin']}>
                          <NotificationsPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route path="*" element={<Navigate to="/" replace />} />
                  </Routes>
                </DashboardLayout>
              </ProtectedRoute>
            }
          />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
