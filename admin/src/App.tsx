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

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { token } = useAuth();
  if (!token) return <Navigate to="/login" replace />;
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
                    <Route path="/approvals" element={<ApprovalsPage />} />
                    <Route path="/companies" element={<CompaniesPage />} />
                    <Route path="/routes" element={<RoutesPage />} />
                    <Route path="/bookings" element={<BookingsPage />} />
                    <Route path="/map" element={<LiveMapPage />} />
                    <Route path="/settings" element={<SettingsPage />} />
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
