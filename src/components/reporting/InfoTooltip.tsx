import React, { useState } from 'react';
import { Info } from 'lucide-react';

interface InfoTooltipProps {
  title: string;
  description: string;
  interpretation: string;
  utility: string;
}

export function InfoTooltip({ title, description, interpretation, utility }: InfoTooltipProps) {
  const [isVisible, setIsVisible] = useState(false);

  return (
    <div className="relative inline-block">
      <button
        onMouseEnter={() => setIsVisible(true)}
        onMouseLeave={() => setIsVisible(false)}
        className="text-gray-400 hover:text-blue-600 transition-colors focus:outline-none"
        type="button"
      >
        <Info className="w-4 h-4" />
      </button>

      {isVisible && (
        <div className="absolute z-50 w-80 p-4 bg-white border border-gray-200 rounded-lg shadow-xl left-6 top-0 pointer-events-none">
          <div className="space-y-3">
            <div>
              <h4 className="font-semibold text-gray-900 mb-1">{title}</h4>
              <p className="text-sm text-gray-600">{description}</p>
            </div>

            <div>
              <h5 className="font-medium text-gray-800 text-sm mb-1">📊 Interpretation</h5>
              <p className="text-sm text-gray-600">{interpretation}</p>
            </div>

            <div>
              <h5 className="font-medium text-gray-800 text-sm mb-1">🎯 Regulatory Utility</h5>
              <p className="text-sm text-gray-600">{utility}</p>
            </div>
          </div>

          {/* Arrow pointing to the icon */}
          <div className="absolute w-2 h-2 bg-white border-l border-t border-gray-200 transform rotate-45 -left-1 top-2"></div>
        </div>
      )}
    </div>
  );
}
