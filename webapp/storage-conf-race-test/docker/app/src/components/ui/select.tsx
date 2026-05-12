import * as RSelect from "@radix-ui/react-select";
import * as RCheckbox from "@radix-ui/react-checkbox";
import * as RRadioGroup from "@radix-ui/react-radio-group";
import * as RSwitch from "@radix-ui/react-switch";

export function Select() {
  return (
    <>
      <RSelect.Root>
        <RSelect.Trigger>
          <RSelect.Value />
        </RSelect.Trigger>
        <RSelect.Portal>
          <RSelect.Content>
            <RSelect.Item value="a">A</RSelect.Item>
          </RSelect.Content>
        </RSelect.Portal>
      </RSelect.Root>
      <RCheckbox.Root />
      <RRadioGroup.Root>
        <RRadioGroup.Item value="a" />
      </RRadioGroup.Root>
      <RSwitch.Root />
    </>
  );
}
