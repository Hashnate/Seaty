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

import { Loader2 } from 'lucide-react';

function LoadingScreen() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900">
      <div className="flex flex-col items-center space-y-4">
        <Loader2 className="h-8 w-8 animate-spin text-indigo-600 dark:text-indigo-400" />
        <p className="text-sm font-medium text-gray-500 dark:text-gray-400">Loading details...</p>
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
