import * as RDialog from "@radix-ui/react-dialog";
import * as RAlertDialog from "@radix-ui/react-alert-dialog";

export function Dialog() {
  return (
    <>
      <RDialog.Root>
        <RDialog.Trigger>Open</RDialog.Trigger>
        <RDialog.Portal>
          <RDialog.Overlay />
          <RDialog.Content>Hello</RDialog.Content>
        </RDialog.Portal>
      </RDialog.Root>
      <RAlertDialog.Root>
        <RAlertDialog.Trigger>Alert</RAlertDialog.Trigger>
        <RAlertDialog.Portal>
          <RAlertDialog.Content>Alert content</RAlertDialog.Content>
        </RAlertDialog.Portal>
      </RAlertDialog.Root>
    </>
  );
}
