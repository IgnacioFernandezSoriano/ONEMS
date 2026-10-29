import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useAccount } from '@/contexts/AccountContext';
import { startOfDayInTz, endOfDayInTz } from '@/lib/dateUtils';
import { calculateJKActualFromDays } from '@/lib/jkCalculations';
import { useEffectiveAccountId } from '../useEffectiveAccountId';
import type { TimeUnit } from '@/lib/accountTime';
import { measureOf, measureUnit } from '@/lib/transitMeasure';

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
  /** Unidad de la medida de la ruta (la del estandar; 'hours' si no hay estandar) */
  unit: TimeUnit;
  /** Estandar en la unidad de la ruta */
  standardTime: number;
  /** J+K real en la unidad de la ruta */
  jkActual: number;
  /** J+K real en horas (dias*24 si la ruta mide en dias) */
  avgBusinessHours: number;
  /** Estandar en horas (dias*24 si la ruta mide en dias) */
  standardHours: number;
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
  /** Media ponderada, en horas */
  avgBusinessHours: number;
  /** Estandar medio ponderado, en horas */
  standardHours: number;
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
  /** Media ponderada, en horas */
  avgBusinessHours: number;
  /** Estandar medio ponderado, en horas */
  standardHours: number;
  standardPercentage: number;
}

export function useComplianceData(accountId: string | undefined, filters?: Filters) {
  const effectiveAccountId = useEffectiveAccountId();
  const { accountTimezone } = useAccount();
  const activeAccountId = effectiveAccountId || accountId;

  const [data, setData] = useState<CarrierData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [globalWarningThreshold, setGlobalWarningThreshold] = useState<number>(80);
  const [globalCriticalThreshold, setGlobalCriticalThreshold] = useState<number>(75);

  useEffect(() => {
    if (!activeAccountId) {
      setLoading(false);
      return;
    }

    async function fetchData() {
      try {
        setLoading(true);
        console.log("[useComplianceData] Filters received:", filters);

        // Build query with filters and pagination
        const allShipments: any[] = []
        const pageSize = 1000
        let start = 0
        let hasMore = true

        while (hasMore) {
          let query = supabase
            .from('one_db')
            .select('*')
            .eq('account_id', activeAccountId)
            .range(start, start + pageSize - 1)

          // Use same date filtering as ONE DB (no time adjustment)
          if (filters?.startDate && filters.startDate !== '') {
            query = query.gte('sent_at', startOfDayInTz(filters.startDate.slice(0, 10), accountTimezone))
          }
          if (filters?.endDate && filters.endDate !== '') {
            query = query.lte('sent_at', endOfDayInTz(filters.endDate.slice(0, 10), accountTimezone))
          }
          if (filters?.originCity) {
            query = query.eq('origin_city_name', filters.originCity)
          }
          if (filters?.destinationCity) {
            query = query.eq('destination_city_name', filters.destinationCity)
          }
          if (filters?.carrier) {
            query = query.eq('carrier_name', filters.carrier)
          }
          if (filters?.product) {
            query = query.eq('product_name', filters.product)
          }

          const { data, error: err } = await query

          if (err) throw err

          if (data && data.length > 0) {
            allShipments.push(...data)
            hasMore = data.length === pageSize
            start += pageSize
          } else {
            hasMore = false
          }
        }

        const shipments = allShipments

        console.log("[useComplianceData] Shipments after query:", shipments?.length);
        console.log('📦 Shipments loaded:', shipments?.length);

        // Load delivery standards WITHOUT JOINs to avoid 400 errors
        const { data: standards, error: stdErr } = await supabase
          .from('delivery_standards')
          .select('*')
          .eq('account_id', activeAccountId);

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
        
        const { data: products, error: productsErr } = await supabase.from('products').select('id, code, description').eq('account_id', accountId);
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
        const productMap = new Map(products?.map(p => [p.id, `${p.code} - ${p.description}`]) || []);
        const cityMap = new Map(cities?.map(c => [c.id, c.name]) || []);

        // Create standards map using UUIDs as key
        const standardsMap = new Map<string, { 
          standardTime: number;
          unit: TimeUnit;
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
            // El estandar se guarda en su propia unidad (sin convertir)
            const unit = measureUnit(std);
            standardsMap.set(key, {
              standardTime: std.standard_time || 0,
              unit,
              successPercentage: std.success_percentage || 0,
              warningThreshold: std.warning_threshold || 5,
              criticalThreshold: std.critical_threshold || 10,
              thresholdType: std.threshold_type || 'relative'
            });
            console.log(`✅ Standard mapped: ${key} -> ${std.standard_time} ${unit}, ${std.success_percentage}%`);
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

        // Calculate global thresholds (average of all standards)
        let warningThreshold = 80;
        let criticalThreshold = 75;
        if (standardsMap.size > 0) {
          const thresholds = Array.from(standardsMap.values()).map(s => {
            const successPct = s.successPercentage;
            const warnThresh = s.thresholdType === 'relative'
              ? successPct - s.warningThreshold
              : s.warningThreshold;
            const critThresh = s.thresholdType === 'relative'
              ? successPct - s.criticalThreshold
              : s.criticalThreshold;
            return { warning: warnThresh, critical: critThresh };
          });
          warningThreshold = thresholds.reduce((sum, t) => sum + t.warning, 0) / thresholds.length;
          criticalThreshold = thresholds.reduce((sum, t) => sum + t.critical, 0) / thresholds.length;
        }
        setGlobalWarningThreshold(warningThreshold);
        setGlobalCriticalThreshold(criticalThreshold);
        console.log('[useComplianceData] Global thresholds:', { warning: warningThreshold, critical: criticalThreshold });

        // Group hierarchically: carrier -> product -> route
        const carrierGroupMap = new Map<string, {
          products: Map<string, {
            routes: Map<string, {
              totalShipments: number;
              compliantShipments: number;
              measureArray: number[];
              unit: TimeUnit;
              standardTime: number;
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
              measureArray: [],
              unit: standard?.unit || 'hours',
              standardTime: standard?.standardTime || 0,
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
          const measured = measureOf(shipment, route.unit);
          if (measured != null) {
            route.measureArray.push(measured);
          }
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
                // Relative: warning = success% - (success% * warning%), critical = success% - (success% * critical%)
                warningLimit = route.standardPercentage - (route.standardPercentage * route.warningThreshold / 100);
                criticalLimit = route.standardPercentage - (route.standardPercentage * route.criticalThreshold / 100);
              } else {
                // Absolute: warning = success% - warning%, critical = success% - critical%
                warningLimit = route.standardPercentage - route.warningThreshold;
                criticalLimit = route.standardPercentage - route.criticalThreshold;
              }
              
              // Determine compliance status based on thresholds
              // Green: actual ≥ warning, Orange: critical < actual < warning, Red: actual ≤ critical
              let complianceStatus: 'compliant' | 'warning' | 'critical';
              if (actualPercentage >= warningLimit) {
                complianceStatus = 'compliant';
              } else if (actualPercentage > criticalLimit) {
                complianceStatus = 'warning';
              } else {
                complianceStatus = 'critical';
              }
              
              const toHours = route.unit === 'days' ? 24 : 1;
              const jkActual = calculateJKActualFromDays(
                route.measureArray,
                route.standardPercentage,
                route.standardTime
              );

              return {
                route: routeKey,
                originCity: route.originCity,
                destinationCity: route.destinationCity,
                totalShipments: route.totalShipments,
                compliantShipments: route.compliantShipments,
                compliancePercentage: actualPercentage,
                unit: route.unit,
                standardTime: route.standardTime,
                jkActual,
                avgBusinessHours: jkActual * toHours,
                standardHours: route.standardTime * toHours,
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
            const productCompliantShipments = routes.reduce((sum, r) => sum + r.compliantShipments, 0);
            const productWarningShipments = routes.reduce((sum, r) => 
              sum + (r.complianceStatus === 'warning' ? r.totalShipments : 0), 0);
            const productCriticalShipments = routes.reduce((sum, r) => 
              sum + (r.complianceStatus === 'critical' ? r.totalShipments : 0), 0);
            
            // Weighted average of standard days (weighted by shipment count)
            const productStandardHours = routes.reduce((sum, r) =>
              sum + (r.standardHours * r.totalShipments), 0) / productTotalShipments;
            
            // Weighted average of standard percentage (weighted by shipment count)
            const productStandardPercentage = routes.reduce((sum, r) => 
              sum + (r.standardPercentage * r.totalShipments), 0) / productTotalShipments;
            
            // Weighted average of actual days (weighted by shipment count)
            const productAvgHours = routes.reduce((sum, r) =>
              sum + (r.avgBusinessHours * r.totalShipments), 0) / productTotalShipments;

            return {
              product: productName,
              routes,
              totalShipments: productTotalShipments,
              compliantShipments: productCompliantShipments,
              warningShipments: productWarningShipments,
              criticalShipments: productCriticalShipments,
              compliancePercentage: (productCompliantShipments / productTotalShipments) * 100,
              avgBusinessHours: productAvgHours,
              standardHours: productStandardHours,
              standardPercentage: productStandardPercentage
            };
          });

          // Calculate weighted averages for carrier level
          const carrierTotalShipments = products.reduce((sum, p) => sum + p.totalShipments, 0);
          const carrierCompliantShipments = products.reduce((sum, p) => sum + p.compliantShipments, 0);
          const carrierWarningShipments = products.reduce((sum, p) => sum + p.warningShipments, 0);
          const carrierCriticalShipments = products.reduce((sum, p) => sum + p.criticalShipments, 0);
          
          // Weighted average of standard days (weighted by shipment count)
          const carrierStandardHours = products.reduce((sum, p) =>
            sum + (p.standardHours * p.totalShipments), 0) / carrierTotalShipments;
          
          // Weighted average of standard percentage (weighted by shipment count)
          const carrierStandardPercentage = products.reduce((sum, p) => 
            sum + (p.standardPercentage * p.totalShipments), 0) / carrierTotalShipments;
          
          // Weighted average of actual days (weighted by shipment count)
          const carrierAvgHours = products.reduce((sum, p) =>
            sum + (p.avgBusinessHours * p.totalShipments), 0) / carrierTotalShipments;

          return {
            carrier: carrierName,
            products,
            totalShipments: carrierTotalShipments,
            compliantShipments: carrierCompliantShipments,
            warningShipments: carrierWarningShipments,
            criticalShipments: carrierCriticalShipments,
            compliancePercentage: (carrierCompliantShipments / carrierTotalShipments) * 100,
            avgBusinessHours: carrierAvgHours,
            standardHours: carrierStandardHours,
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
  }, [activeAccountId, filters?.startDate, filters?.endDate, filters?.originCity, filters?.destinationCity, filters?.carrier, filters?.product, filters?.complianceStatus, accountTimezone]);

  return { data, loading, error, globalWarningThreshold, globalCriticalThreshold };
}
