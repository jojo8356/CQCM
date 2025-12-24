import { Dialog } from '@kobalte/core/dialog';
import { Show, type JSXElement } from 'solid-js';
import { FiX } from 'solid-icons/fi';

type ModalProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  children: JSXElement;
};

export default function Modal(props: ModalProps) {
  return (
    <Dialog open={props.open} onOpenChange={props.onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay class="fixed inset-0 z-50 bg-black/50" />
        <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
          <Dialog.Content class="w-full max-w-md bg-white rounded-xl shadow-2xl animate-scale-in overflow-hidden">
            <div class="p-6">
              <div class="flex items-start justify-between gap-4 mb-4">
                <Dialog.Title class="text-xl font-bold text-gray-800 flex-1">
                  {props.title}
                </Dialog.Title>
                <Dialog.CloseButton class="flex-shrink-0 p-1.5 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors cursor-pointer">
                  <FiX size={20} />
                </Dialog.CloseButton>
              </div>
              <Show when={props.description}>
                <Dialog.Description class="text-gray-600 text-sm mb-4">
                  {props.description}
                </Dialog.Description>
              </Show>
              <div class="w-full">
                {props.children}
              </div>
            </div>
          </Dialog.Content>
        </div>
      </Dialog.Portal>
    </Dialog>
  );
}
