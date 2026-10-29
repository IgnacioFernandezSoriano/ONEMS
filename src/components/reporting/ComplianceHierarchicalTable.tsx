import React, { useState, useMemo, useEffect } from 'react';
import { ChevronDown, ChevronRight, Download } from 'lucide-react';
import { downloadRouteSamples } from '@/utils/downloadRouteSamples';
import { useTimeUnit } from '@/hooks/useTimeUnit';
import type { TimeUnit } from '@/lib/accountTime';
import { aggregateJK, formatJK } from '@/lib/transitMeasure';

interface RouteData {
  origin: string;
  destination: string;
  carrier: string;
  product: string;
  totalShipments: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  unit: TimeUnit; // unidad del estandar de la ruta (la de jkStandard/jkActual)
  jkStandard: number;
  jkActual: number;
  status: 'compliant' | 'warning' | 'critical';
  carrierUnit?: TimeUnit;
  carrierJkStandard?: number;
  carrierJkActual?: number;
  carrierStandardPercentage?: number;
  carrierActualPercentage?: number;
  carrierDeviation?: number;
  carrierStatus?: 'compliant' | 'warning' | 'critical';
  productUnit?: TimeUnit;
  productJkStandard?: number;
  productJkActual?: number;
  productStandardPercentage?: number;
  productActualPercentage?: number;
  productDeviation?: number;
  productStatus?: 'compliant' | 'warning' | 'critical';
}

interface ComplianceHierarchicalTableProps {
  data: RouteData[];
  warningThreshold: number;
  criticalThreshold: number;
}

export function ComplianceHierarchicalTable({ data, warningThreshold, criticalThreshold }: ComplianceHierarchicalTableProps) {
  const { unit: displayUnit } = useTimeUnit();
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set());
  const [expandedProducts, setExpandedProducts] = useState<Set<string>>(new Set());

  // Auto-expand carriers and products on mount
  useEffect(() => {
    if (data.length > 0) {
      const carriers = new Set<string>();
      data.forEach(route => {
        carriers.add(route.carrier || 'Unknown');
      });
      setExpandedCarriers(carriers);
    }
  }, [data]);

  // Aggregate data by carrier → product → route
  const hierarchicalData = useMemo(() => {
    const carrierMap = new Map();
    
    data.forEach(route => {
      const carrier = route.carrier || 'Unknown';
      const product = route.product || 'Unknown';
      
      if (!carrierMap.has(carrier)) {
        carrierMap.set(carrier, {
          carrier,
          totalSamples: 0,
          products: new Map(),
        });
      }
      
      const carrierData = carrierMap.get(carrier);
      
      if (!carrierData.products.has(product)) {
        carrierData.products.set(product, {
          product,
          routes: [],
        });
      }
      
      const productData = carrierData.products.get(product);
      productData.routes.push(route);
    });
    
    // Calculate product metrics from visible routes
    return Array.from(carrierMap.values()).map((carrierData: any) => {
      const products = Array.from(carrierData.products.values()).map((productData: any) => {
        const routes = productData.routes;
        const totalSamples = routes.reduce((sum: number, r: RouteData) => sum + (r.totalShipments || 0), 0);
        
        // Weighted averages for product (J+K en la unidad comun de sus rutas; horas si mezclan)
        const jk = aggregateJK(routes.map((r: RouteData) => ({
          unit: r.unit,
          jkStandard: r.jkStandard,
          jkActual: r.jkActual,
          totalSamples: r.totalShipments || 0,
        })));
        const standardPercentageSum = routes.reduce((sum: number, r: RouteData) => sum + (r.standardPercentage * r.totalShipments), 0);
        const actualPercentageSum = routes.reduce((sum: number, r: RouteData) => sum + (r.actualPercentage * r.totalShipments), 0);
        
        const standardPercentage = totalSamples > 0 ? standardPercentageSum / totalSamples : 0;
        const actualPercentage = totalSamples > 0 ? actualPercentageSum / totalSamples : 0;
        const deviation = actualPercentage - standardPercentage;
        
        // Product status: worst status from routes
        const routeStatuses = routes.map((r: RouteData) => r.status);
        const hasCritical = routeStatuses.some((s: string) => s === 'critical');
        const hasWarning = routeStatuses.some((s: string) => s === 'warning');
        const status = hasCritical ? 'critical' : hasWarning ? 'warning' : 'compliant';
        
        return {
          product: productData.product,
          totalSamples,
          unit: jk.unit,
          jkStandard: jk.jkStandard,
          jkActual: jk.jkActual,
          standardPercentage,
          actualPercentage,
          deviation,
          status,
          routes,
        };
      });
      
      // Calculate carrier metrics from visible products
      const totalSamples = products.reduce((sum: number, p: any) => sum + p.totalSamples, 0);
      const jk = aggregateJK(products);
      const standardPercentageSum = products.reduce((sum: number, p: any) => sum + (p.standardPercentage * p.totalSamples), 0);
      const actualPercentageSum = products.reduce((sum: number, p: any) => sum + (p.actualPercentage * p.totalSamples), 0);
      
      const standardPercentage = totalSamples > 0 ? standardPercentageSum / totalSamples : 0;
      const actualPercentage = totalSamples > 0 ? actualPercentageSum / totalSamples : 0;
      const deviation = actualPercentage - standardPercentage;
      
      // Carrier status: worst status from products
      const productStatuses = products.map((p: any) => p.status);
      const hasCritical = productStatuses.some((s: string) => s === 'critical');
      const hasWarning = productStatuses.some((s: string) => s === 'warning');
      const status = hasCritical ? 'critical' : hasWarning ? 'warning' : 'compliant';
      
      return {
        carrier: carrierData.carrier,
        totalSamples,
        unit: jk.unit,
        jkStandard: jk.jkStandard,
        jkActual: jk.jkActual,
        standardPercentage,
        actualPercentage,
        deviation,
        status,
        products,
      };
    });
  }, [data]);

  const toggleCarrier = (carrier: string) => {
    const newExpanded = new Set(expandedCarriers);
    if (newExpanded.has(carrier)) {
      newExpanded.delete(carrier);
    } else {
      newExpanded.add(carrier);
    }
    setExpandedCarriers(newExpanded);
  };

  const toggleProduct = (carrierProduct: string) => {
    const newExpanded = new Set(expandedProducts);
    if (newExpanded.has(carrierProduct)) {
      newExpanded.delete(carrierProduct);
    } else {
      newExpanded.add(carrierProduct);
    }
    setExpandedProducts(newExpanded);
  };

  const handleDownloadCSV = (route: RouteData) => {
    downloadRouteSamples({
      originCity: route.origin,
      destinationCity: route.destination,
      carrier: route.carrier,
      product: route.product,
    });
  };

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Carrier / Product / Route
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Samples</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">J+K STD</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">J+K Actual</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">STD %</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actual %</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Deviation</th>
            <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
            <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {hierarchicalData.map((carrierItem) => (
            <React.Fragment key={carrierItem.carrier}>
              {/* Carrier Row */}
              <tr className="bg-blue-50 hover:bg-blue-100 cursor-pointer" onClick={() => toggleCarrier(carrierItem.carrier)}>
                <td className="px-4 py-3 whitespace-nowrap text-sm font-bold">
                  <div className="flex items-center gap-2">
                    {expandedCarriers.has(carrierItem.carrier) ? (
                      <ChevronDown className="w-4 h-4" />
                    ) : (
                      <ChevronRight className="w-4 h-4" />
                    )}
                    {carrierItem.carrier}
                  </div>
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-bold">{carrierItem.totalSamples}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-bold">
                  {carrierItem.jkStandard > 0 ? formatJK(carrierItem.jkStandard, carrierItem.unit, displayUnit) : '-'}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-bold">
                  {carrierItem.jkActual > 0 ? formatJK(carrierItem.jkActual, carrierItem.unit, displayUnit) : '-'}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-bold">
                  {carrierItem.standardPercentage > 0 ? `${carrierItem.standardPercentage.toFixed(1)}%` : '-'}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-bold text-gray-900">
                  {carrierItem.actualPercentage > 0 ? `${carrierItem.actualPercentage.toFixed(1)}%` : '-'}
                </td>
                <td className={`px-4 py-3 whitespace-nowrap text-sm text-right font-bold ${
                  carrierItem.deviation < 0 ? 'text-red-600' : 'text-gray-900'
                }`}>
                  {carrierItem.deviation !== 0 ? `${carrierItem.deviation.toFixed(1)}%` : '-'}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-center">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                    carrierItem.status === 'compliant' ? 'bg-green-100 text-green-800' :
                    carrierItem.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                    'bg-red-100 text-red-800'
                  }`}>
                    {carrierItem.status}
                  </span>
                </td>
                <td></td>
              </tr>
              
              {/* Products under this carrier */}
              {expandedCarriers.has(carrierItem.carrier) && carrierItem.products.map((productItem: any) => (
                <React.Fragment key={`${carrierItem.carrier}-${productItem.product}`}>
                  {/* Product Row */}
                  <tr 
                    className="bg-gray-50 hover:bg-gray-100 cursor-pointer" 
                    onClick={() => toggleProduct(`${carrierItem.carrier}-${productItem.product}`)}
                  >
                    <td className="px-4 py-3 whitespace-nowrap text-sm font-semibold pl-12">
                      <div className="flex items-center gap-2">
                        {expandedProducts.has(`${carrierItem.carrier}-${productItem.product}`) ? (
                          <ChevronDown className="w-4 h-4" />
                        ) : (
                          <ChevronRight className="w-4 h-4" />
                        )}
                        {productItem.product}
                      </div>
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-semibold">{productItem.totalSamples}</td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-semibold">
                      {productItem.jkStandard > 0 ? formatJK(productItem.jkStandard, productItem.unit, displayUnit) : '-'}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-semibold">
                      {productItem.jkActual > 0 ? formatJK(productItem.jkActual, productItem.unit, displayUnit) : '-'}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-semibold">
                      {productItem.standardPercentage > 0 ? `${productItem.standardPercentage.toFixed(1)}%` : '-'}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-semibold text-gray-900">
                      {productItem.actualPercentage > 0 ? `${productItem.actualPercentage.toFixed(1)}%` : '-'}
                    </td>
                    <td className={`px-4 py-3 whitespace-nowrap text-sm text-right font-semibold ${
                      productItem.deviation < 0 ? 'text-red-600' : 'text-gray-900'
                    }`}>
                      {productItem.deviation !== 0 ? `${productItem.deviation.toFixed(1)}%` : '-'}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-center">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                        productItem.status === 'compliant' ? 'bg-green-100 text-green-800' :
                        productItem.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                        'bg-red-100 text-red-800'
                      }`}>
                        {productItem.status}
                      </span>
                    </td>
                    <td></td>
                  </tr>
                  
                  {/* Routes under this product */}
                  {expandedProducts.has(`${carrierItem.carrier}-${productItem.product}`) && productItem.routes.map((route: RouteData, idx: number) => {
                    const deviation = route.deviation.toFixed(1);
                    
                    return (
                      <tr 
                        key={idx} 
                        className="hover:bg-gray-50 cursor-pointer"
                        onClick={() => {
                          const url = `/reporting/territory-equity?tab=jk&hideSidebar=true&origin=${encodeURIComponent(route.origin)}&destination=${encodeURIComponent(route.destination)}&carrier=${encodeURIComponent(route.carrier)}&product=${encodeURIComponent(route.product)}`;
                          window.open(url, '_blank');
                        }}
                      >
                        <td className="px-4 py-3 whitespace-nowrap text-sm pl-20">
                          {route.origin} → {route.destination}
                        </td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.totalShipments || 0}</td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.jkStandard > 0 ? formatJK(route.jkStandard, route.unit, displayUnit) : '-'}</td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.jkActual > 0 ? formatJK(route.jkActual, route.unit, displayUnit) : '-'}</td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.standardPercentage?.toFixed(1)}%</td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-900">
                          {route.actualPercentage?.toFixed(1)}%
                        </td>
                        <td className={`px-4 py-3 whitespace-nowrap text-sm text-right ${
                          parseFloat(deviation) < 0 ? 'text-red-600' : 'text-gray-900'
                        }`}>
                          {deviation}%
                        </td>
                        <td className="px-4 py-3 whitespace-nowrap text-center">
                          <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                            route.status === 'compliant' ? 'bg-green-100 text-green-800' :
                            route.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                            'bg-red-100 text-red-800'
                          }`}>
                            {route.status}
                          </span>
                        </td>
                        <td className="px-4 py-3 whitespace-nowrap text-center">
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              handleDownloadCSV(route);
                            }}
                            className="text-blue-600 hover:text-blue-800"
                            title="Download samples CSV"
                          >
                            <Download className="w-4 h-4" />
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </React.Fragment>
              ))}
            </React.Fragment>
          ))}
        </tbody>
      </table>
      {hierarchicalData.length === 0 && (
        <div className="text-center py-8 text-gray-500">
          No compliance data available
        </div>
      )}
    </div>
  );
}
