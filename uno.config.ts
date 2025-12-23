import { defineConfig, presetUno, presetIcons } from 'unocss';

export default defineConfig({
  presets: [
    presetUno(),
    presetIcons(),
  ],
  shortcuts: {
    'btn': 'px-4 py-2 rounded-lg cursor-pointer transition-all duration-200',
    'card': 'bg-white rounded-xl shadow-lg p-6',
  },
});
