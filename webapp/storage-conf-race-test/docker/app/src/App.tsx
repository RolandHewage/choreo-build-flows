import { DropdownMenu } from "./components/ui/dropdown-menu";
import { Dialog } from "./components/ui/dialog";
import { Popover } from "./components/ui/popover";
import { Select } from "./components/ui/select";
import { Tabs } from "./components/ui/tabs";
import { Accordion } from "./components/ui/accordion";
import { Tooltip } from "./components/ui/tooltip";
import { Toast } from "./components/ui/toast";
import { NavigationMenu } from "./components/ui/navigation-menu";
import { ContextMenu } from "./components/ui/context-menu";
import { Menubar } from "./components/ui/menubar";
import { HoverCard } from "./components/ui/hover-card";

export default function App() {
  return (
    <div>
      <h1>Storage conf race reproducer</h1>
      <DropdownMenu />
      <Dialog />
      <Popover />
      <Select />
      <Tabs />
      <Accordion />
      <Tooltip />
      <Toast />
      <NavigationMenu />
      <ContextMenu />
      <Menubar />
      <HoverCard />
    </div>
  );
}
