import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { adjustStartDateForFilter, adjustEndDateForFilter } from '@/lib/dateUtils';

interface Filters {
  startDate?: string;
  endDate?: string;
  originCity?: string;
  destinationCity?: string;
  carrier?: string;
  product?: string;
  complianceStatus?: string;
}

export interface RouteData {
  route: string;
  originCity: string;
  destinationCity: string;
  totalShipments: number;
  compliantShipments: number;
  compliancePercentage: number;
  avgBusinessDays: number;
  standardDays: number;
  standardPercentage: number;
  warningThreshold: number;
  criticalThreshold: number;
  thresholdType: 'relative' | 'absolute';
  warningLimit: number;
  criticalLimit: number;
  complianceStatus: 'compliant' | 'warning' | 'critical';
}

export interface ProductData {
  product: string;
  routes: RouteData[];
  totalShipments: number;
  compliantShipments: number;
  warningShipments: number;
  criticalShipments: number;
  compliancePercentage: number;
  avgBusinessDays: number;
  standardDays: number;
  standardPercentage: number;
}

export interface CarrierData {
  carrier: string;
  products: ProductData[];
  totalShipments: number;
  compliantShipments: number;
  warningShipments: number;
  criticalShipments: number;
  compliancePercentage: number;
  avgBusinessDays: number;
  standardDays: number;
  standardPercentage: number;
}

export function useComplianceData(accountId: string | undefined, filters?: Filters) {
  const [data, setData] = useState<CarrierData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!accountId) {
      setLoading(false);
      return;
    }

    async function fetchData() {
      try {
        setLoading(true);
        console.log("[useComplianceData] Filters received:", filters);

        // Build query with filters
        let query = supabase
          .from('one_db')
          .select('*')
          .eq('account_id', accountId);

        if (filters?.startDate && filters.startDate !== '') {
          query = query.gte('sent_at', adjustStartDateForFilter(filters.startDate));
        }
        if (filters?.endDate && filters.endDate !== '') {
          query = query.lte('sent_at', adjustEndDateForFilter(filters.endDate));
        }
        if (filters?.originCity) {
          query = query.eq('origin_city_name', filters.originCity);
        }
        if (filters?.destinationCity) {
          query = query.eq('destination_city_name', filters.destinationCity);
        }
        if (filters?.carrier) {
          query = query.eq('carrier_name', filters.carrier);
        }
        if (filters?.product) {
          query = query.eq('product_name', filters.product);
        }

        const { data: shipments, error: err } = await query;

        if (err) throw err;

        console.log("[useComplianceData] Shipments after query:", shipments?.length);
        console.log('📦 Shipments loaded:', shipments?.length);

        // Load delivery standards WITHOUT JOINs to avoid 400 errors
        const { data: standards, error: stdErr } = await supabase
          .from('delivery_standards')
          .select('*')
          .eq('account_id', accountId);

        if (stdErr) {
          console.error('❌ Error loading standards:', stdErr);
          throw stdErr;
        }

        console.log('📏 Delivery standards loaded:', standards?.length);
        console.log('📏 First standard example:', standards?.[0]);

        // Load lookup tables
        const { data: carriers, error: carriersErr } = await supabase.from('carriers').select('id, name').eq('account_id', accountId);
        if (carriersErr) {
          console.error('❌ Error loading carriers:', carriersErr);
        }
        
        const { data: products, error: productsErr } = await supabase.from('products').select('id, description').eq('account_id', accountId);
        if (productsErr) {
          console.error('❌ Error loading products:', productsErr);
          console.error('❌ Products error details:', JSON.stringify(productsErr));
        }
        
        const { data: cities, error: citiesErr } = await supabase.from('cities').select('id, name').eq('account_id', accountId);
        if (citiesErr) {
          console.error('❌ Error loading cities:', citiesErr);
        }

        console.log('🏢 Carriers loaded:', carriers?.length);
        console.log('📦 Products loaded:', products?.length);
        console.log('🌆 Cities loaded:', cities?.length);

        // Create lookup maps
        const carrierMap = new Map(carriers?.map(c => [c.id, c.name]) || []);
        const productMap = new Map(products?.map(p => [p.id, p.description]) || []);
        const cityMap = new Map(cities?.map(c => [c.id, c.name]) || []);

        // Create standards map using UUIDs as key
        const standardsMap = new Map<string, { 
          allowedDays: number; 
          successPercentage: number;
          warningThreshold: number;
          criticalThreshold: number;
          thresholdType: 'relative' | 'absolute';
        }>();
        
        (standards || []).forEach(std => {
          const carrierName = carrierMap.get(std.carrier_id);
          const productName = productMap.get(std.product_id);
          const originName = cityMap.get(std.origin_city_id);
          const destName = cityMap.get(std.destination_city_id);
          
          if (carrierName && productName && originName && destName) {
            const key = `${carrierName}|${productName}|${originName}|${destName}`;
            // Convert standard_time to days
            const allowedDays = std.time_unit === 'days' 
              ? std.standard_time 
              : (std.standard_time / 24);
            standardsMap.set(key, {
              allowedDays: allowedDays || 0,
              successPercentage: std.success_percentage || 0,
              warningThreshold: std.warning_threshold || 5,
              criticalThreshold: std.critical_threshold || 10,
              thresholdType: std.threshold_type || 'relative'
            });
            console.log(`✅ Standard mapped: ${key} -> ${allowedDays} days, ${std.success_percentage}%`);
          } else {
            console.warn('⚠️ Incomplete standard data:', { 
              carrier_id: std.carrier_id, 
              carrierName,
              product_id: std.product_id,
              productName,
              origin_city_id: std.origin_city_id,
              originName,
              destination_city_id: std.destination_city_id,
              destName
            });
          }
        });

        console.log('📊 Standards map size:', standardsMap.size);
        console.log('📊 Standards map keys:', Array.from(standardsMap.keys()));

        // Group hierarchically: carrier -> product -> route
        const carrierGroupMap = new Map<string, {
          products: Map<string, {
            routes: Map<string, {
              totalShipments: number;
              compliantShipments: number;
              totalDays: number;
              standardDays: number;
              standardPercentage: number;
              warningThreshold: number;
              criticalThreshold: number;
              thresholdType: 'relative' | 'absolute';
              originCity: string;
              destinationCity: string;
            }>;
          }>;
        }>();

        (shipments || []).forEach(shipment => {
          const carrierName = shipment.carrier_name;
          const productName = shipment.product_name;
          const routeKey = `${shipment.origin_city_name} → ${shipment.destination_city_name}`;
          
          // Get standard for this specific carrier+product+route
          const standardKey = `${carrierName}|${productName}|${shipment.origin_city_name}|${shipment.destination_city_name}`;
          const standard = standardsMap.get(standardKey);

          if (!standard) {
            console.warn(`⚠️ No standard found for: ${standardKey}`);
          }

          // Initialize carrier if not exists
          if (!carrierGroupMap.has(carrierName)) {
            carrierGroupMap.set(carrierName, { products: new Map() });
          }
          
          const carrier = carrierGroupMap.get(carrierName)!;
          
          // Initialize product if not exists
          if (!carrier.products.has(productName)) {
            carrier.products.set(productName, { routes: new Map() });
          }
          
          const product = carrier.products.get(productName)!;
          
          // Initialize route if not exists
          if (!product.routes.has(routeKey)) {
            product.routes.set(routeKey, {
              totalShipments: 0,
              compliantShipments: 0,
              totalDays: 0,
              standardDays: standard?.allowedDays || 0,
              standardPercentage: standard?.successPercentage || 0,
              warningThreshold: standard?.warningThreshold || 5,
              criticalThreshold: standard?.criticalThreshold || 10,
              thresholdType: standard?.thresholdType || 'relative',
              originCity: shipment.origin_city_name,
              destinationCity: shipment.destination_city_name
            });
          }
          
          const route = product.routes.get(routeKey)!;
          route.totalShipments++;
          route.compliantShipments += shipment.on_time_delivery ? 1 : 0;
          route.totalDays += shipment.business_transit_days || 0;
        });

        // Convert to array structure with weighted averages
        const result: CarrierData[] = Array.from(carrierGroupMap.entries()).map(([carrierName, carrier]) => {
          const products: ProductData[] = Array.from(carrier.products.entries()).map(([productName, product]) => {
            const routes: RouteData[] = Array.from(product.routes.entries()).map(([routeKey, route]) => {
              const actualPercentage = (route.compliantShipments / route.totalShipments) * 100;
              
              // Calculate threshold limits
              let warningLimit: number;
              let criticalLimit: number;
              
              if (route.thresholdType === 'relative') {
                // Relative: threshold is % of success_percentage
                warningLimit = route.standardPercentage - (route.standardPercentage * route.warningThreshold / 100);
                criticalLimit = route.standardPercentage - (route.standardPercentage * route.criticalThreshold / 100);
              } else {
                // Absolute: threshold is % of 100
                warningLimit = 100 - route.warningThreshold;
                criticalLimit = 100 - route.criticalThreshold;
              }
              
              // Determine compliance status
              let complianceStatus: 'compliant' | 'warning' | 'critical';
              if (actualPercentage >= route.standardPercentage) {
                complianceStatus = 'compliant';
              } else if (actualPercentage >= warningLimit) {
                complianceStatus = 'warning';
              } else if (actualPercentage >= criticalLimit) {
                complianceStatus = 'warning'; // Still warning zone
              } else {
                complianceStatus = 'critical';
              }
              
              return {
                route: routeKey,
                originCity: route.originCity,
                destinationCity: route.destinationCity,
                totalShipments: route.totalShipments,
                compliantShipments: route.compliantShipments,
                compliancePercentage: actualPercentage,
                avgBusinessDays: route.totalDays / route.totalShipments,
                standardDays: route.standardDays,
                standardPercentage: route.standardPercentage,
                warningThreshold: route.warningThreshold,
                criticalThreshold: route.criticalThreshold,
                thresholdType: route.thresholdType,
                warningLimit,
                criticalLimit,
                complianceStatus
              };
            });

            // Calculate weighted averages for product level
            const productTotalShipments = routes.reduce((sum, r) => sum + r.totalShipments, 0);
            const productCompliantShipments = routes.reduce((sum, r) => 
              sum + (r.complianceStatus === 'compliant' ? r.totalShipments : 0), 0);
            const productWarningShipments = routes.reduce((sum, r) => 
              sum + (r.complianceStatus === 'warning' ? r.totalShipments : 0), 0);
            const productCriticalShipments = routes.reduce((sum, r) => 
              sum + (r.complianceStatus === 'critical' ? r.totalShipments : 0), 0);
            
            // Weighted average of standard days (weighted by shipment count)
            const productStandardDays = routes.reduce((sum, r) => 
              sum + (r.standardDays * r.totalShipments), 0) / productTotalShipments;
            
            // Weighted average of standard percentage (weighted by shipment count)
            const productStandardPercentage = routes.reduce((sum, r) => 
              sum + (r.standardPercentage * r.totalShipments), 0) / productTotalShipments;
            
            // Weighted average of actual days (weighted by shipment count)
            const productAvgDays = routes.reduce((sum, r) => 
              sum + (r.avgBusinessDays * r.totalShipments), 0) / productTotalShipments;

            return {
              product: productName,
              routes,
              totalShipments: productTotalShipments,
              compliantShipments: productCompliantShipments,
              warningShipments: productWarningShipments,
              criticalShipments: productCriticalShipments,
              compliancePercentage: (productCompliantShipments / productTotalShipments) * 100,
              avgBusinessDays: productAvgDays,
              standardDays: productStandardDays,
              standardPercentage: productStandardPercentage
            };
          });

          // Calculate weighted averages for carrier level
          const carrierTotalShipments = products.reduce((sum, p) => sum + p.totalShipments, 0);
          const carrierCompliantShipments = products.reduce((sum, p) => sum + p.compliantShipments, 0);
          const carrierWarningShipments = products.reduce((sum, p) => sum + p.warningShipments, 0);
          const carrierCriticalShipments = products.reduce((sum, p) => sum + p.criticalShipments, 0);
          
          // Weighted average of standard days (weighted by shipment count)
          const carrierStandardDays = products.reduce((sum, p) => 
            sum + (p.standardDays * p.totalShipments), 0) / carrierTotalShipments;
          
          // Weighted average of standard percentage (weighted by shipment count)
          const carrierStandardPercentage = products.reduce((sum, p) => 
            sum + (p.standardPercentage * p.totalShipments), 0) / carrierTotalShipments;
          
          // Weighted average of actual days (weighted by shipment count)
          const carrierAvgDays = products.reduce((sum, p) => 
            sum + (p.avgBusinessDays * p.totalShipments), 0) / carrierTotalShipments;

          return {
            carrier: carrierName,
            products,
            totalShipments: carrierTotalShipments,
            compliantShipments: carrierCompliantShipments,
            warningShipments: carrierWarningShipments,
            criticalShipments: carrierCriticalShipments,
            compliancePercentage: (carrierCompliantShipments / carrierTotalShipments) * 100,
            avgBusinessDays: carrierAvgDays,
            standardDays: carrierStandardDays,
            standardPercentage: carrierStandardPercentage
          };
        });

        console.log('📊 Final result:', result);
        
        // Apply compliance status filter if specified
        let filteredResult = result;
        if (filters?.complianceStatus && filters.complianceStatus.trim() !== '') {
          const selectedStatuses = filters.complianceStatus.split(',').filter(Boolean);
          filteredResult = result.map(carrier => ({
            ...carrier,
            products: carrier.products.map(product => ({
              ...product,
              routes: product.routes.filter(route => selectedStatuses.includes(route.complianceStatus))
            })).filter(product => product.routes.length > 0)
          })).filter(carrier => carrier.products.length > 0);
        }
        
        setData(filteredResult);
      } catch (err) {
        console.error('❌ Error in fetchData:', err);
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [accountId, filters?.startDate, filters?.endDate, filters?.originCity, filters?.destinationCity, filters?.carrier, filters?.product, filters?.complianceStatus]);

  return { data, loading, error };
}
