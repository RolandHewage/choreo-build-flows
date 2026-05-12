import * as RMenubar from "@radix-ui/react-menubar";

export function Menubar() {
  return (
    <RMenubar.Root>
      <RMenubar.Menu>
        <RMenubar.Trigger>File</RMenubar.Trigger>
        <RMenubar.Portal>
          <RMenubar.Content>
            <RMenubar.Item>New</RMenubar.Item>
          </RMenubar.Content>
        </RMenubar.Portal>
      </RMenubar.Menu>
    </RMenubar.Root>
  );
}
