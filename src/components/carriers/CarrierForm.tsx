import { useState } from 'react'
import type { Carrier } from '@/lib/types'
import {
  CAPTURE_METHODS,
  CAPTURE_METHOD_LABEL_KEY,
  captureMethodOf,
  carrierWritePayload,
  isValidNotificationEmail,
  normalizeNotificationEmail,
  showsNotificationEmail,
  type CaptureMethod,
} from '@/lib/carrierCapture'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useCarrierLinkUi } from '@/hooks/useCarrierLinkUi'

import { useTranslation } from '@/hooks/useTranslation';

interface CarrierFormProps {
  carrier?: Carrier
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function CarrierForm({ carrier, onSubmit, onCancel }: CarrierFormProps) {
  const { t } = useTranslation();
  const { canEdit } = usePermissions()
  // Forma de captura solo en cuentas con Carrier Link; en las demás, el formulario es el de siempre.
  const carrierLinkOn = useCarrierLinkUi()
  // Correo de avisos de Carrier Link: solo con Carrier Link y para quien edita carriers; si no, ni se ve ni se envía.
  const withEmail = showsNotificationEmail(carrierLinkOn, canEdit('carriers'))
  const [formData, setFormData] = useState({
    code: carrier?.code || '',
    name: carrier?.name || '',
    type: carrier?.type || '',
    status: carrier?.status || 'active',
    capture_method: carrier ? captureMethodOf(carrier) : ('panelists' as CaptureMethod),
  })
  const [notificationEmail, setNotificationEmail] = useState(carrier?.notification_email ?? '')
  const [emailError, setEmailError] = useState(false)
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (withEmail && !isValidNotificationEmail(normalizeNotificationEmail(notificationEmail))) {
      setEmailError(true)
      return
    }
    setLoading(true)
    try {
      // Solo se envía si la columna ya existe en la fila leída o si se ha escrito un correo (antes de aplicar la
      // migración de incidencias, guardar un carrier en DEV sigue funcionando).
      const sendEmail = withEmail && ((!!carrier && 'notification_email' in carrier) || notificationEmail.trim() !== '')
      await onSubmit(carrierWritePayload(sendEmail ? { ...formData, notification_email: notificationEmail } : formData, carrierLinkOn))
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label className="block text-sm font-medium mb-1">{t('hc.carrier_form.code')} *</label>
        <input
          type="text"
          required
          value={formData.code}
          onChange={(e) => setFormData({ ...formData, code: e.target.value.toUpperCase() })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder={t('hc.carrier_form.code_placeholder')}
          maxLength={20}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">{t('hc.carrier_form.name')} *</label>
        <input
          type="text"
          required
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder={t('hc.carrier_form.name_placeholder')}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">{t('stock.type')}</label>
        <input
          type="text"
          value={formData.type}
          onChange={(e) => setFormData({ ...formData, type: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder={t('hc.carrier_form.type_placeholder')}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">{t('hc.carrier_form.status')} *</label>
        <select
          required
          value={formData.status}
          onChange={(e) => setFormData({ ...formData, status: e.target.value as any })}
          className="w-full px-3 py-2 border rounded-md"
        >
          <option value="active">{t('common.active')}</option>
          <option value="inactive">{t('common.inactive')}</option>
        </select>
      </div>

      {carrierLinkOn && <div>
        <label className="block text-sm font-medium mb-1">{t('cl.capture_method.label')} *</label>
        <select
          required
          value={formData.capture_method}
          onChange={(e) => setFormData({ ...formData, capture_method: e.target.value as CaptureMethod })}
          className="w-full px-3 py-2 border rounded-md"
        >
          {CAPTURE_METHODS.map((m) => (
            <option key={m} value={m}>{t(CAPTURE_METHOD_LABEL_KEY[m])}</option>
          ))}
        </select>
        <p className="text-xs text-gray-500 mt-1">{t('cl.capture_method.help')}</p>
      </div>}

      {withEmail && <div>
        <label className="block text-sm font-medium mb-1">{t('cl.carrier.notification_email')}</label>
        <input
          type="email"
          value={notificationEmail}
          maxLength={254}
          onChange={(e) => {
            setNotificationEmail(e.target.value)
            setEmailError(false)
          }}
          className="w-full px-3 py-2 border rounded-md"
          dir="ltr"
        />
        <p className="text-xs text-gray-500 mt-1">{t('cl.carrier.notification_email_help')}</p>
        {emailError && <p className="text-xs text-red-600 mt-1">{t('cl.carrier.notification_email_invalid')}</p>}
      </div>}

      <div className="flex gap-2 justify-end">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 text-gray-700 hover:bg-gray-100 rounded-md"
        >
          {t('hc.carrier_form.cancel')}
        </button>
        <button
          type="submit"
          disabled={loading}
          className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? t('hc.carrier_form.saving') : carrier ? t('hc.carrier_form.update') : t('hc.carrier_form.create')}
        </button>
      </div>
    </form>
  )
}
