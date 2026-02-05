import React, { useState, useMemo } from 'react';
import { ChevronDown, ChevronRight, Download } from 'lucide-react';
import { downloadRouteSamples } from '@/utils/downloadRouteSamples';

interface RouteData {
  origin: string;
  destination: string;
  carrier: string;
  product: string;
  totalShipments: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  standardDays: number;
  actualDays: number;
  status: 'compliant' | 'warning' | 'critical';
}

interface ComplianceHierarchicalTableProps {
  data: RouteData[];
  warningThreshold: number;
  criticalThreshold: number;
}

export function ComplianceHierarchicalTable({ data, warningThreshold, criticalThreshold }: ComplianceHierarchicalTableProps) {
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set());
  const [expandedProducts, setExpandedProducts] = useState<Set<string>>(new Set());

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
      carrierData.totalSamples += route.totalShipments || 0;
      
      if (!carrierData.products.has(product)) {
        carrierData.products.set(product, {
          product,
          totalSamples: 0,
          routes: [],
        });
      }
      
      const productData = carrierData.products.get(product);
      productData.totalSamples += route.totalShipments || 0;
      productData.routes.push(route);
    });
    
    return Array.from(carrierMap.values()).map(c => ({
      ...c,
      products: Array.from(c.products.values()),
    }));
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
                <td colSpan={7}></td>
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
                    <td colSpan={7}></td>
                  </tr>
                  
                  {/* Routes under this product */}
                  {expandedProducts.has(`${carrierItem.carrier}-${productItem.product}`) && productItem.routes.map((route: RouteData, idx: number) => {
                    const deviation = route.deviation.toFixed(1);
                    
                    return (
                      <tr key={idx} className="hover:bg-gray-50">
                        <td className="px-4 py-3 whitespace-nowrap text-sm pl-20">
                          {route.origin} → {route.destination}
                        </td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.totalShipments || 0}</td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.standardDays?.toFixed(1)}</td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.actualDays?.toFixed(1)}</td>
                        <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.standardPercentage?.toFixed(1)}%</td>
                        <td className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                          route.status === 'compliant' ? 'text-green-600' :
                          route.status === 'warning' ? 'text-amber-600' : 'text-red-600'
                        }`}>
                          {route.actualPercentage?.toFixed(1)}%
                        </td>
                        <td className={`px-4 py-3 whitespace-nowrap text-sm text-right ${
                          parseFloat(deviation) < 0 ? 'text-red-600' : 'text-gray-600'
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
