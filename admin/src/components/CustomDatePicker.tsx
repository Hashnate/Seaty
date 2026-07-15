import React, { useState, useRef, useEffect } from 'react';
import { Calendar as CalendarIcon, ChevronLeft, ChevronRight } from 'lucide-react';

interface CustomDatePickerProps {
  value: string; // YYYY-MM-DD
  onChange: (value: string) => void;
  style?: React.CSSProperties;
}

export default function CustomDatePicker({ value, onChange, style }: CustomDatePickerProps) {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Parse the current value
  const parsedDate = value ? new Date(value) : new Date();
  
  // Local calendar view state
  const [viewDate, setViewDate] = useState(parsedDate);

  // Close calendar popover on click outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Update view Date when value changes from parent
  useEffect(() => {
    if (value) {
      setViewDate(new Date(value));
    }
  }, [value]);

  const year = viewDate.getFullYear();
  const month = viewDate.getMonth(); // 0-indexed

  // Month names
  const MONTH_NAMES = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // Days of week
  const DAYS_OF_WEEK = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  // Get days in month
  const getDaysInMonth = (y: number, m: number) => new Date(y, m + 1, 0).getDate();
  
  // Get first weekday of month (0 = Sun, 6 = Sat)
  const getFirstWeekday = (y: number, m: number) => new Date(y, m, 1).getDay();

  const daysInCurrentMonth = getDaysInMonth(year, month);
  const firstWeekday = getFirstWeekday(year, month);

  // Previous month padding days
  const prevMonthIdx = month === 0 ? 11 : month - 1;
  const prevMonthYear = month === 0 ? year - 1 : year;
  const daysInPrevMonth = getDaysInMonth(prevMonthYear, prevMonthIdx);

  const prevMonthPaddingDays = Array.from(
    { length: firstWeekday },
    (_, i) => daysInPrevMonth - firstWeekday + 1 + i
  );

  // Current month days
  const currentMonthDays = Array.from({ length: daysInCurrentMonth }, (_, i) => i + 1);

  // Next month padding days (to fill the grid to multiple of 7, say 42 cells)
  const totalCells = 42;
  const nextMonthPaddingCount = totalCells - (prevMonthPaddingDays.length + currentMonthDays.length);
  const nextMonthPaddingDays = Array.from({ length: nextMonthPaddingCount }, (_, i) => i + 1);

  const handlePrevMonth = () => {
    setViewDate(new Date(year, month - 1, 1));
  };

  const handleNextMonth = () => {
    setViewDate(new Date(year, month + 1, 1));
  };

  const selectDay = (day: number, isCurrentMonth = true, isPrevMonth = false) => {
    let selYear = year;
    let selMonth = month;
    if (isPrevMonth) {
      selMonth = month === 0 ? 11 : month - 1;
      selYear = month === 0 ? year - 1 : year;
    } else if (!isCurrentMonth) {
      selMonth = month === 11 ? 0 : month + 1;
      selYear = month === 11 ? year + 1 : year;
    }

    const formattedMonth = String(selMonth + 1).padStart(2, '0');
    const formattedDay = String(day).padStart(2, '0');
    const dateStr = `${selYear}-${formattedMonth}-${formattedDay}`;
    onChange(dateStr);
    setIsOpen(false);
  };

  const isToday = (day: number) => {
    const today = new Date();
    return today.getDate() === day && today.getMonth() === month && today.getFullYear() === year;
  };

  const isSelected = (day: number) => {
    if (!value) return false;
    // We compare strings to avoid timezone mismatch issues
    const formattedMonth = String(month + 1).padStart(2, '0');
    const formattedDay = String(day).padStart(2, '0');
    const dateStr = `${year}-${formattedMonth}-${formattedDay}`;
    return value === dateStr;
  };

  // Format date for trigger button display: e.g. "Jul 16, 2026"
  const getFormattedDisplayDate = () => {
    if (!value) return 'Select Date';
    // Use split to extract date components directly to avoid timezone offsetting
    const parts = value.split('-');
    if (parts.length === 3) {
      const yearStr = parts[0];
      const monthIdx = parseInt(parts[1], 10) - 1;
      const dayStr = parseInt(parts[2], 10);
      const monthStr = MONTH_NAMES[monthIdx]?.substring(0, 3);
      return `${monthStr} ${dayStr}, ${yearStr}`;
    }
    return value;
  };

  return (
    <div ref={containerRef} style={{ position: 'relative', ...style }}>
      {/* Trigger */}
      <div
        onClick={() => setIsOpen(!isOpen)}
        style={{
          width: '100%',
          padding: '12px 16px',
          background: '#1e293b',
          border: isOpen ? '1.5px solid #e65100' : '1px solid rgba(255,255,255,0.1)',
          borderRadius: '10px',
          color: 'white',
          fontSize: '14px',
          cursor: 'pointer',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          userSelect: 'none',
          boxShadow: isOpen ? '0 0 12px rgba(230, 81, 0, 0.25)' : 'none',
          transition: 'all 0.15s ease'
        }}
      >
        <span>{getFormattedDisplayDate()}</span>
        <CalendarIcon size={16} style={{ color: 'rgba(255,255,255,0.4)' }} />
      </div>

      {/* Calendar Dropdown Popover */}
      {isOpen && (
        <div
          style={{
            position: 'absolute',
            top: '100%',
            left: 0,
            marginTop: '6px',
            background: '#0b0f19',
            border: '1px solid rgba(255,255,255,0.12)',
            borderRadius: '16px',
            boxShadow: '0 10px 25px -5px rgba(0, 0, 0, 0.5)',
            zIndex: 1020,
            width: '280px',
            padding: '16px',
            userSelect: 'none',
            color: 'white'
          }}
        >
          {/* Header (Prev, Month Year, Next) */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
            <button
              type="button"
              onClick={handlePrevMonth}
              style={{
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid rgba(255,255,255,0.08)',
                color: 'white',
                borderRadius: '8px',
                cursor: 'pointer',
                width: '32px',
                height: '32px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                transition: 'all 0.15s ease'
              }}
              onMouseEnter={(e) => e.currentTarget.style.background = 'rgba(255,255,255,0.1)'}
              onMouseLeave={(e) => e.currentTarget.style.background = 'rgba(255,255,255,0.04)'}
            >
              <ChevronLeft size={16} />
            </button>
            <span style={{ fontSize: '13px', fontWeight: 700 }}>
              {MONTH_NAMES[month]} {year}
            </span>
            <button
              type="button"
              onClick={handleNextMonth}
              style={{
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid rgba(255,255,255,0.08)',
                color: 'white',
                borderRadius: '8px',
                cursor: 'pointer',
                width: '32px',
                height: '32px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                transition: 'all 0.15s ease'
              }}
              onMouseEnter={(e) => e.currentTarget.style.background = 'rgba(255,255,255,0.1)'}
              onMouseLeave={(e) => e.currentTarget.style.background = 'rgba(255,255,255,0.04)'}
            >
              <ChevronRight size={16} />
            </button>
          </div>

          {/* Weekday headers */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: '4px', textAlign: 'center', marginBottom: '8px' }}>
            {DAYS_OF_WEEK.map(day => (
              <span key={day} style={{ fontSize: '11px', fontWeight: 600, color: 'rgba(255,255,255,0.4)', textTransform: 'uppercase' }}>
                {day}
              </span>
            ))}
          </div>

          {/* Days Grid */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: '4px' }}>
            {/* Prev month padding */}
            {prevMonthPaddingDays.map((d, i) => (
              <div
                key={`prev-${i}`}
                onClick={() => selectDay(d, true, true)}
                style={{
                  height: '30px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: '12px',
                  color: 'rgba(255,255,255,0.2)',
                  cursor: 'pointer',
                  borderRadius: '6px'
                }}
              >
                {d}
              </div>
            ))}

            {/* Current month days */}
            {currentMonthDays.map(d => {
              const active = isSelected(d);
              const today = isToday(d);
              return (
                <div
                  key={`day-${d}`}
                  onClick={() => selectDay(d)}
                  onMouseEnter={(e) => {
                    if (!active) {
                      e.currentTarget.style.background = 'rgba(230, 81, 0, 0.08)';
                    }
                  }}
                  onMouseLeave={(e) => {
                    if (!active) {
                      e.currentTarget.style.background = 'transparent';
                    }
                  }}
                  style={{
                    height: '30px',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: '12px',
                    cursor: 'pointer',
                    borderRadius: '6px',
                    background: active ? '#e65100' : 'transparent',
                    color: 'white',
                    fontWeight: active || today ? 700 : 400,
                    border: today && !active ? '1px solid #e65100' : 'none',
                    transition: 'all 0.15s ease'
                  }}
                >
                  {d}
                </div>
              );
            })}

            {/* Next month padding */}
            {nextMonthPaddingDays.map((d, i) => (
              <div
                key={`next-${i}`}
                onClick={() => selectDay(d, false)}
                style={{
                  height: '30px',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: '12px',
                  color: 'rgba(255,255,255,0.2)',
                  cursor: 'pointer',
                  borderRadius: '6px'
                }}
              >
                {d}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
