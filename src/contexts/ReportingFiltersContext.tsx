import React, { createContext, useContext, useState, ReactNode } from 'react';

export interface ReportingFilters {
  startDate: string;
  endDate: string;
  carrier: string;
  product: string;
  routeType: string;
  originCity: string;
  destinationCity: string;
  complianceStatus?: string;
}

interface ReportingFiltersContextType {
  filters: ReportingFilters;
  setFilters: (filters: ReportingFilters) => void;
  updateFilter: (key: keyof ReportingFilters, value: string) => void;
  resetFilters: () => void;
}

const defaultFilters: ReportingFilters = {
  startDate: '',
  endDate: '',
  carrier: '',
  product: '',
  routeType: '',
  originCity: '',
  destinationCity: '',
  complianceStatus: ''
};

const ReportingFiltersContext = createContext<ReportingFiltersContextType | undefined>(undefined);

export function ReportingFiltersProvider({ children }: { children: ReactNode }) {
  const [filters, setFilters] = useState<ReportingFilters>(defaultFilters);

  const updateFilter = (key: keyof ReportingFilters, value: string) => {
    setFilters(prev => ({
      ...prev,
      [key]: value
    }));
  };

  const resetFilters = () => {
    setFilters(defaultFilters);
  };

  return (
    <ReportingFiltersContext.Provider value={{ filters, setFilters, updateFilter, resetFilters }}>
      {children}
    </ReportingFiltersContext.Provider>
  );
}

export function useReportingFilters() {
  const context = useContext(ReportingFiltersContext);
  if (context === undefined) {
    throw new Error('useReportingFilters must be used within a ReportingFiltersProvider');
  }
  return context;
}
