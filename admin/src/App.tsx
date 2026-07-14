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
import ContractorsPage from './pages/ContractorsPage';

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { token } = useAuth();
  if (!token) return <Navigate to="/login" replace />;
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
                        <RoleProtectedRoute allowed={['owner']}>
                          <MyFleetPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/trips" 
                      element={
                        <RoleProtectedRoute allowed={['owner']}>
                          <MyTripsPage />
                        </RoleProtectedRoute>
                      } 
                    />
                    <Route 
                      path="/contractors" 
                      element={
                        <RoleProtectedRoute allowed={['owner']}>
                          <ContractorsPage />
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
