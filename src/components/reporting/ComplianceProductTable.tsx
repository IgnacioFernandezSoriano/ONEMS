import React, { useState } from 'react';
import { ArrowUpDown, ChevronDown, ChevronRight } from 'lucide-react';

interface ProductData {
  product: string;
  routes: any[];
  totalSamples: number;
  compliantRoutes: number;
  warningRoutes: number;
  criticalRoutes: number;
}

interface ComplianceProductTableProps {
  data: ProductData[];
  warningThreshold: number;
  criticalThreshold: number;
}

export function ComplianceProductTable({ data, warningThreshold, criticalThreshold }: ComplianceProductTableProps) {
  const [expandedProducts, setExpandedProducts] = useState<Set<string>>(new Set());

  const toggleProduct = (product: string) => {
    const newExpanded = new Set(expandedProducts);
    if (newExpanded.has(product)) {
      newExpanded.delete(product);
    } else {
      newExpanded.add(product);
    }
    setExpandedProducts(newExpanded);
  };

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-12"></th>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Total Samples</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Routes</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Compliant</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Warning</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Critical</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Compliance %</th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {data.map((product) => {
            const isExpanded = expandedProducts.has(product.product);
            const complianceRate = product.routes.length > 0 ? (product.compliantRoutes / product.routes.length) * 100 : 0;
            return (
              <React.Fragment key={product.product}>
                <tr className="hover:bg-gray-50 cursor-pointer" onClick={() => toggleProduct(product.product)}>
                  <td className="px-4 py-3 whitespace-nowrap">
                    {isExpanded ? <ChevronDown className="w-4 h-4 text-gray-400" /> : <ChevronRight className="w-4 h-4 text-gray-400" />}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm font-medium">{product.product}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{product.totalSamples}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{product.routes.length}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-green-600">{product.compliantRoutes}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-amber-600">{product.warningRoutes}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-red-600">{product.criticalRoutes}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right font-medium">{complianceRate.toFixed(1)}%</td>
                </tr>
                {isExpanded && product.routes.map((route, idx) => (
                  <tr key={idx} className="bg-gray-50">
                    <td className="px-4 py-2"></td>
                    <td className="px-4 py-2 text-sm text-gray-600 pl-8">{route.origin} → {route.destination}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.samples || 0}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.carrier}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.standardDays?.toFixed(1)}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.actualDays?.toFixed(1)}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.actualPercentage?.toFixed(1)}%</td>
                    <td className="px-4 py-2 text-sm text-right">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                        route.status === 'compliant' ? 'bg-green-100 text-green-800' :
                        route.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                        'bg-red-100 text-red-800'
                      }`}>
                        {route.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </React.Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
