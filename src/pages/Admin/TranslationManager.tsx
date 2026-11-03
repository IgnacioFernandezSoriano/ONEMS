import { useState } from 'react'
import { Upload, Download, CheckCircle, AlertCircle, FileText } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useTranslation } from '@/hooks/useTranslation'

export default function TranslationManager() {
  const { t } = useTranslation()
  const [uploading, setUploading] = useState(false)
  const [uploadStatus, setUploadStatus] = useState<{
    type: 'success' | 'error' | null
    message: string
  }>({ type: null, message: '' })

  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return

    setUploading(true)
    setUploadStatus({ type: null, message: '' })

    try {
      // Validate file type
      if (!file.name.endsWith('.csv')) {
        throw new Error(t('hc.translation_manager.upload_csv_error'))
      }

      // Read file content
      const text = await file.text()
      
      // Validate CSV structure
      const lines = text.split('\n').filter(line => line.trim())
      if (lines.length < 2) {
        throw new Error(t('hc.translation_manager.empty_csv'))
      }

      const header = lines[0].toLowerCase()
      const requiredColumns = ['key', 'en', 'es', 'fr', 'ar', 'pt']
      const missingColumns = requiredColumns.filter(col => !header.includes(col))
      
      if (missingColumns.length > 0) {
        throw new Error(t('hc.translation_manager.missing_columns', { columns: missingColumns.join(', ') }))
      }

      // Count translations
      const translationCount = lines.length - 1 // Exclude header
      
      // Extract language-specific CSVs and upload to Supabase Storage
      const languages = ['en', 'es', 'fr', 'ar', 'pt']
      const headerParts = lines[0].split(',')
      const keyIdx = headerParts.findIndex(h => h.trim().toLowerCase() === 'key')
      
      let uploadedCount = 0
      
      for (const lang of languages) {
        const langIdx = headerParts.findIndex(h => h.trim().toLowerCase() === lang)
        if (langIdx === -1) continue

        // Build CSV content for this language
        let langCSV = 'key,translation\n'
        
        for (let i = 1; i < lines.length; i++) {
          const parts = lines[i].split(',')
          const key = parts[keyIdx]?.trim()
          const translation = parts[langIdx]?.trim()
          
          if (key && translation) {
            // Escape commas in translation if needed
            const escapedTranslation = translation.includes(',') ? `"${translation}"` : translation
            langCSV += `${key},${escapedTranslation}\n`
          }
        }

        // Upload to Supabase Storage
        const blob = new Blob([langCSV], { type: 'text/csv;charset=utf-8;' })
        const fileName = `${lang}.csv`
        
        // Delete existing file if it exists
        await supabase.storage
          .from('translations')
          .remove([fileName])
        
        // Upload new file
        const { error: uploadError } = await supabase.storage
          .from('translations')
          .upload(fileName, blob, {
            contentType: 'text/csv',
            upsert: true
          })

        if (uploadError) {
          throw new Error(t('hc.translation_manager.upload_failed', { file: `${lang}.csv`, message: uploadError.message }))
        }
        
        uploadedCount++
      }

      setUploadStatus({
        type: 'success',
        message: t('hc.translation_manager.success', { count: translationCount, files: uploadedCount })
      })
    } catch (error) {
      setUploadStatus({
        type: 'error',
        message: error instanceof Error ? error.message : t('hc.translation_manager.process_failed')
      })
    } finally {
      setUploading(false)
      // Reset file input
      event.target.value = ''
    }
  }

  const downloadTemplate = () => {
    const link = document.createElement('a')
    link.href = '/translations_template.csv'
    link.download = 'translations_template.csv'
    link.click()
  }

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">{t('hc.translation_manager.title')}</h1>
        <p className="text-gray-600 mt-2">
          {t('hc.translation_manager.subtitle')}
        </p>
      </div>

      {/* Instructions */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-6 mb-6">
        <h2 className="text-lg font-semibold text-blue-900 mb-3 flex items-center gap-2">
          <FileText className="w-5 h-5" />
          {t('hc.translation_manager.how_to_use')}
        </h2>
        <ol className="list-decimal list-inside space-y-2 text-blue-800">
          <li>{t('hc.translation_manager.step_a')}</li>
          <li>{t('hc.translation_manager.step_b')}</li>
          <li>{t('hc.translation_manager.step_c')}</li>
          <li>{t('hc.translation_manager.step_d')}</li>
          <li className="font-semibold">✨ {t('hc.translation_manager.auto_applied')}</li>
        </ol>
      </div>

      {/* Download Template */}
      <div className="bg-white border border-gray-200 rounded-lg p-6 mb-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-3">{t('hc.translation_manager.step1_title')}</h2>
        <p className="text-gray-600 mb-4">
          {t('hc.translation_manager.step1_desc')}
        </p>
        <button
          onClick={downloadTemplate}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
        >
          <Download className="w-4 h-4" />
          {t('hc.translation_manager.download_template')}
        </button>
      </div>

      {/* Upload Translated CSV */}
      <div className="bg-white border border-gray-200 rounded-lg p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-3">{t('hc.translation_manager.step2_title')}</h2>
        <p className="text-gray-600 mb-4">
          {t('hc.translation_manager.step2_desc')}
        </p>
        
        <div className="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center">
          <Upload className="w-12 h-12 text-gray-400 mx-auto mb-4" />
          <label className="cursor-pointer">
            <span className="text-blue-600 hover:text-blue-700 font-medium">
              {t('hc.translation_manager.click_to_upload')}
            </span>
            <span className="text-gray-600"> {t('hc.translation_manager.or_drag_drop')}</span>
            <input
              type="file"
              accept=".csv"
              onChange={handleFileUpload}
              disabled={uploading}
              className="hidden"
            />
          </label>
          <p className="text-sm text-gray-500 mt-2">{t('hc.translation_manager.csv_only')}</p>
        </div>

        {/* Upload Status */}
        {uploadStatus.type && (
          <div
            className={`mt-4 p-4 rounded-lg flex items-start gap-3 ${
              uploadStatus.type === 'success'
                ? 'bg-green-50 border border-green-200'
                : 'bg-red-50 border border-red-200'
            }`}
          >
            {uploadStatus.type === 'success' ? (
              <CheckCircle className="w-5 h-5 text-green-600 flex-shrink-0 mt-0.5" />
            ) : (
              <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            )}
            <p
              className={
                uploadStatus.type === 'success' ? 'text-green-800' : 'text-red-800'
              }
            >
              {uploadStatus.message}
            </p>
          </div>
        )}

        {uploading && (
          <div className="mt-4 text-center">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
            <p className="text-gray-600 mt-2">{t('hc.translation_manager.processing')}</p>
          </div>
        )}
      </div>

      {/* Current Languages */}
      <div className="bg-white border border-gray-200 rounded-lg p-6 mt-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-3">{t('hc.translation_manager.supported_languages')}</h2>
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
          {[
            { code: 'en', name: 'English', flag: '🇬🇧' },
            { code: 'es', name: 'Español', flag: '🇪🇸' },
            { code: 'fr', name: 'Français', flag: '🇫🇷' },
            { code: 'ar', name: 'العربية', flag: '🇸🇦' },
            { code: 'pt', name: 'Português', flag: '🇵🇹' }
          ].map(lang => (
            <div
              key={lang.code}
              className="border border-gray-200 rounded-lg p-4 text-center"
            >
              <div className="text-3xl mb-2">{lang.flag}</div>
              <div className="font-medium text-gray-900">{lang.name}</div>
              <div className="text-sm text-gray-500">{lang.code.toUpperCase()}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
