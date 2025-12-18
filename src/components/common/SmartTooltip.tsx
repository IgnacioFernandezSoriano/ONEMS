import { useState } from 'react'

interface SmartTooltipProps {
  content: string | React.ReactNode
  children?: React.ReactNode
}

export function SmartTooltip({ content, children }: SmartTooltipProps) {
  const [isVisible, setIsVisible] = useState(false)

  return (
    <div className="relative inline-block">
      <div
        onMouseEnter={() => setIsVisible(true)}
        onMouseLeave={() => setIsVisible(false)}
        className="cursor-help"
      >
        {children || (
          <svg className="w-3.5 h-3.5 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
            <path
              fillRule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z"
              clipRule="evenodd"
            />
          </svg>
        )}
      </div>

      {/* Tooltip Modal - Fixed position, centered, professional design */}
      {isVisible && (
        <>
          {/* Backdrop overlay */}
          <div 
            className="fixed inset-0 bg-black bg-opacity-20 z-[9998]" 
            style={{ pointerEvents: 'none' }}
          />
          
          {/* Tooltip content - centered, professional styling */}
          <div 
            className="fixed top-1/3 left-1/2 transform -translate-x-1/2 -translate-y-1/2 z-[9999] max-w-2xl w-auto px-4"
            style={{ pointerEvents: 'none' }}
          >
            <div className="bg-white rounded-xl shadow-2xl border-2 border-blue-500 overflow-hidden">
              {/* Header with gradient */}
              <div className="bg-gradient-to-r from-blue-600 to-blue-500 px-6 py-3 flex items-center gap-3">
                <svg className="w-6 h-6 text-white flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <h3 className="text-white font-semibold text-base">Information</h3>
              </div>
              
              {/* Content */}
              <div className="px-6 py-5 bg-white">
                <div className="text-gray-700 text-sm leading-relaxed font-normal">
                  {content}
                </div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
