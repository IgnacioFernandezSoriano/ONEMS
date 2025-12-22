import React, { useState } from 'react'
import type { AllocationPlanDetailWithRelations } from '@/lib/types'
import { RegisterShipmentModal } from './RegisterShipmentModal'
import { RegisterReceptionModal } from './RegisterReceptionModal'
import { getISOWeekFromDate } from '@/utils/weekUtils'

interface Props {
  detail: AllocationPlanDetailWithRelations
  nodes: any[]
  panelists: any[]
  selected: boolean
  onToggleSelect: () => void
  onUpdate: (id: string, updates: any) => Promise<void>
  onMarkAsSent: (id: string, data: any) => Promise<void>
  onEdit: (detail: AllocationPlanDetailWithRelations) => void
  getNodesByCity: (cityId: string) => any[]
}

export function AllocationPlanDetailRow({
  detail,
  nodes,
  panelists,
  selected,
  onToggleSelect,
  onUpdate,
  onMarkAsSent,
  onEdit,
  getNodesByCity,
}: Props) {
  const [editing, setEditing] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [showShipmentModal, setShowShipmentModal] = useState(false)
  const [showReceptionModal, setShowReceptionModal] = useState(false)

  // Determine if record is editable
  const isCompleted = detail.status === 'received'
  const isNonEditable = ['sent', 'received', 'cancelled', 'invalid'].includes(detail.status) || isCompleted
  const canEdit = !isNonEditable

  const originNodes = detail.origin_city_id ? getNodesByCity(detail.origin_city_id) : []
  const destinationNodes = detail.destination_city_id ? getNodesByCity(detail.destination_city_id) : []

  const handleUpdate = async (field: string, value: any) => {
    try {
      setSaving(true)
      
      // If updating fecha_programada, calculate week_number and year automatically
      if (field === 'fecha_programada') {
        const { year, week_number } = getISOWeekFromDate(value)
        await onUpdate(detail.id, { 
          [field]: value,
          year,
          week_number
        })
      } else {
        await onUpdate(detail.id, { [field]: value })
      }
      
      setEditing(null)
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
    <tr className={`${selected ? 'bg-blue-50' : ''} hover:bg-gray-50`}>
      {/* Checkbox */}
      <td className="px-4 py-3">
        <input
          type="checkbox"
          checked={selected}
          onChange={onToggleSelect}
          className="rounded border-gray-300"
        />
      </td>

      {/* Plan */}
      <td className="px-4 py-3 text-sm">{detail.plan?.plan_name}</td>

      {/* Carrier */}
      <td className="px-4 py-3 text-sm">{detail.carrier?.name}</td>

      {/* Product */}
      <td className="px-4 py-3 text-sm">{detail.product?.description}</td>

      {/* Origin City */}
      <td className="px-4 py-3 text-sm font-medium">{detail.origin_city?.name}</td>

      {/* Origin Node - Editable */}
      <td className="px-4 py-3 text-sm">
        {editing === 'origin_node' && canEdit ? (
          <select
            value={detail.origin_node_id}
            onChange={(e) => handleUpdate('origin_node_id', e.target.value)}
            onBlur={() => setEditing(null)}
            autoFocus
            className="w-full border rounded px-2 py-1 text-sm"
            disabled={saving}
          >
            {originNodes.map((node) => (
              <option key={node.id} value={node.id}>
                {node.auto_id}
              </option>
            ))}
          </select>
        ) : (
          <button
            onClick={() => canEdit && setEditing('origin_node')}
            className={`text-left w-full ${canEdit ? 'hover:text-blue-600 cursor-pointer' : 'cursor-not-allowed text-gray-500'}`}
            disabled={!canEdit}
          >
            {detail.origin_node?.auto_id}
          </button>
        )}
      </td>

      {/* Destination City */}
      <td className="px-4 py-3 text-sm font-medium">{detail.destination_city?.name}</td>

      {/* Destination Node - Editable */}
      <td className="px-4 py-3 text-sm">
        {editing === 'destination_node' && canEdit ? (
          <select
            value={detail.destination_node_id}
            onChange={(e) => handleUpdate('destination_node_id', e.target.value)}
            onBlur={() => setEditing(null)}
            autoFocus
            className="w-full border rounded px-2 py-1 text-sm"
            disabled={saving}
          >
            {destinationNodes.map((node) => (
              <option key={node.id} value={node.id}>
                {node.auto_id}
              </option>
            ))}
          </select>
        ) : (
          <button
            onClick={() => canEdit && setEditing('destination_node')}
            className={`text-left w-full ${canEdit ? 'hover:text-blue-600 cursor-pointer' : 'cursor-not-allowed text-gray-500'}`}
            disabled={!canEdit}
          >
            {detail.destination_node?.auto_id}
          </button>
        )}
      </td>

      {/* Scheduled Date - Editable */}
      <td className="px-4 py-3 text-sm">
        {editing === 'fecha_programada' && canEdit ? (
          <input
            type="date"
            value={detail.fecha_programada}
            onChange={(e) => handleUpdate('fecha_programada', e.target.value)}
            onBlur={() => setEditing(null)}
            autoFocus
            className="w-full border rounded px-2 py-1 text-sm"
            disabled={saving}
          />
        ) : (
          <button
            onClick={() => canEdit && setEditing('fecha_programada')}
            className={`text-left w-full ${canEdit ? 'hover:text-blue-600 cursor-pointer' : 'cursor-not-allowed text-gray-500'}`}
            disabled={!canEdit}
          >
            {detail.fecha_programada}
          </button>
        )}
      </td>

      {/* Week */}
      <td className="px-4 py-3 text-sm text-gray-600">
        {detail.year}-W{String(detail.week_number).padStart(2, '0')}
      </td>

      {/* Tag ID - Editable */}
      <td className="px-4 py-3 text-sm">
        {editing === 'tag_id' && canEdit ? (
          <input
            type="text"
            value={detail.tag_id || ''}
            onChange={(e) => handleUpdate('tag_id', e.target.value)}
            onBlur={() => setEditing(null)}
            autoFocus
            className="w-full border rounded px-2 py-1 text-sm"
            disabled={saving}
            placeholder="Enter tag ID"
          />
        ) : (
          <button
            onClick={() => canEdit && setEditing('tag_id')}
            className={`text-left w-full ${canEdit ? 'hover:text-blue-600 cursor-pointer' : 'cursor-not-allowed text-gray-500'}`}
            disabled={!canEdit}
          >
            {detail.tag_id || <span className="text-gray-400">-</span>}
          </button>
        )}
      </td>

      {/* Origin Panelist */}
      <td className="px-4 py-3 text-sm text-gray-600">
        {detail.origin_panelist_name || <span className="text-gray-400">Not assigned</span>}
      </td>

      {/* Origin Availability Status */}
      <td className="px-4 py-3">
        {detail.origin_availability_status === 'unavailable' ? (
          <div className="flex flex-col gap-1">
            <span className="px-2 py-1 rounded text-xs bg-red-100 text-red-800 font-semibold">
              ⚠ UNAVAILABLE
            </span>
            {detail.origin_unavailability_reason && (
              <span className="text-xs text-gray-500">
                {detail.origin_unavailability_reason}
              </span>
            )}
          </div>
        ) : detail.origin_availability_status === 'unassigned' ? (
          <span className="px-2 py-1 rounded text-xs bg-gray-100 text-gray-600">
            Unassigned
          </span>
        ) : detail.origin_availability_status === 'inactive' ? (
          <span className="px-2 py-1 rounded text-xs bg-gray-300 text-gray-700">
            Inactive
          </span>
        ) : (
          <span className="px-2 py-1 rounded text-xs bg-green-100 text-green-800">
            ✓ Available
          </span>
        )}
      </td>

      {/* Destination Panelist */}
      <td className="px-4 py-3 text-sm text-gray-600">
        {detail.destination_panelist_name || <span className="text-gray-400">Not assigned</span>}
      </td>

      {/* Destination Availability Status */}
      <td className="px-4 py-3">
        {detail.destination_availability_status === 'unavailable' ? (
          <div className="flex flex-col gap-1">
            <span className="px-2 py-1 rounded text-xs bg-red-100 text-red-800 font-semibold">
              ⚠ UNAVAILABLE
            </span>
            {detail.destination_unavailability_reason && (
              <span className="text-xs text-gray-500">
                {detail.destination_unavailability_reason}
              </span>
            )}
          </div>
        ) : detail.destination_availability_status === 'unassigned' ? (
          <span className="px-2 py-1 rounded text-xs bg-gray-100 text-gray-600">
            Unassigned
          </span>
        ) : detail.destination_availability_status === 'inactive' ? (
          <span className="px-2 py-1 rounded text-xs bg-gray-300 text-gray-700">
            Inactive
          </span>
        ) : (
          <span className="px-2 py-1 rounded text-xs bg-green-100 text-green-800">
            ✓ Available
          </span>
        )}
      </td>

      {/* Status */}
      <td className="px-4 py-3">
        {detail.status === 'invalid' && detail.validation_errors ? (
          <div className="group relative inline-block">
            <span className="px-2 py-1 rounded text-xs font-medium bg-red-100 text-red-800 border border-red-300 cursor-help">
              ⚠ Invalid
            </span>
            <div className="absolute z-50 invisible group-hover:visible bg-gray-900 text-white text-xs rounded py-2 px-3 bottom-full left-0 mb-2 w-64 shadow-lg">
              <div className="font-semibold mb-1">Validation Errors:</div>
              <ul className="list-disc list-inside space-y-1">
                {detail.validation_errors.map((error, idx) => (
                  <li key={idx}>{error}</li>
                ))}
              </ul>
              <div className="absolute top-full left-4 -mt-1 border-4 border-transparent border-t-gray-900"></div>
            </div>
          </div>
        ) : detail.status === 'transfer_error' ? (
          <div className="group relative inline-block">
            <span className="px-2 py-1 rounded text-xs font-medium bg-orange-100 text-orange-800 border border-orange-300 cursor-help">
              ⚠ Transfer Error
            </span>
            {detail.transfer_error_message && (
              <div className="absolute z-50 invisible group-hover:visible bg-gray-900 text-white text-xs rounded py-2 px-3 bottom-full left-0 mb-2 w-64 shadow-lg">
                <div className="font-semibold mb-1">Error:</div>
                <div>{detail.transfer_error_message}</div>
                <div className="absolute top-full left-4 -mt-1 border-4 border-transparent border-t-gray-900"></div>
              </div>
            )}
          </div>
        ) : (
          <span
            className={`px-2 py-1 rounded text-xs font-medium ${
              detail.status === 'received'
                ? 'bg-green-100 text-green-800'
                : detail.status === 'sent'
                ? 'bg-blue-100 text-blue-800'
                : detail.status === 'notified'
                ? 'bg-cyan-100 text-cyan-800'
                : detail.status === 'cancelled'
                ? 'bg-red-100 text-red-800'
                : 'bg-yellow-100 text-yellow-800' // pending
            }`}
          >
            {detail.status}
          </span>
        )}
      </td>

      {/* Actions */}
      <td className="px-4 py-3">
        <div className="flex gap-2 items-center">
          {canEdit && (
            <button
              onClick={() => onEdit(detail)}
              className="p-1 text-gray-600 hover:text-blue-600 hover:bg-blue-50 rounded transition-colors"
              title="Edit record"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
              </svg>
            </button>
          )}
          
          {detail.status === 'pending' || detail.status === 'notified' ? (
            <button
              onClick={() => setShowShipmentModal(true)}
              className="px-3 py-1 bg-blue-600 text-white rounded text-xs hover:bg-blue-700"
              title="Register shipment"
            >
              Send
            </button>
          ) : null}
          
          {detail.status === 'sent' ? (
            <button
              onClick={() => setShowReceptionModal(true)}
              className="px-3 py-1 bg-green-600 text-white rounded text-xs hover:bg-green-700"
              title="Register reception"
            >
              Receive
            </button>
          ) : null}
          
          {detail.status === 'received' ? (
            <span className="text-xs text-gray-500">Completed</span>
          ) : null}
          
          {detail.status === 'cancelled' ? (
            <span className="text-xs text-gray-500">Cancelled</span>
          ) : null}
        </div>
      </td>
    </tr>
    
    {/* Modals */}
    {showShipmentModal && (
      <RegisterShipmentModal
        detail={detail}
        panelists={panelists}
        onClose={() => setShowShipmentModal(false)}
        onRegister={async (data) => {
          await onMarkAsSent(detail.id, data)
          setShowShipmentModal(false)
        }}
      />
    )}
    
    {showReceptionModal && (
      <RegisterReceptionModal
        detail={detail}
        panelists={panelists}
        onClose={() => setShowReceptionModal(false)}
        onRegister={async (data) => {
          await onUpdate(detail.id, {
            ...data,
            status: 'received',
          })
          setShowReceptionModal(false)
        }}
      />
    )}
  </>
  )
}
