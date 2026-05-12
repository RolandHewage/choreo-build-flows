import * as RToast from "@radix-ui/react-toast";

export function Toast() {
  return (
    <RToast.Provider>
      <RToast.Root>
        <RToast.Title>Title</RToast.Title>
        <RToast.Description>Body</RToast.Description>
      </RToast.Root>
      <RToast.Viewport />
    </RToast.Provider>
  );
}
