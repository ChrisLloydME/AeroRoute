from __future__ import annotations

import sys
from pathlib import Path

from PySide6.QtCore import QByteArray, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QFont, QKeySequence, QPalette, QShortcut
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QColorDialog,
    QFileDialog,
    QFormLayout,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSpinBox,
    QSplitter,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
    QDoubleSpinBox,
)
from PySide6.QtSvgWidgets import QSvgWidget

from .fr24 import ImportedLeg, load_fr24
from .model import TrackDataError, combine_tracks, validate_leg_order
from .svg import MapStyle, RenderOptions, build_svg, write_svg


class FlightList(QListWidget):
    files_dropped = Signal(list)
    order_changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        self.setAcceptDrops(True)
        self.setDragEnabled(True)
        self.setDragDropMode(QListWidget.DragDropMode.InternalMove)
        self.setDefaultDropAction(Qt.DropAction.MoveAction)
        self.model().rowsMoved.connect(lambda *_: self.order_changed.emit())

    def dragEnterEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.mimeData().hasUrls() or event.source() is self:
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def dragMoveEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
        else:
            super().dragMoveEvent(event)

    def dropEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.mimeData().hasUrls():
            paths = [url.toLocalFile() for url in event.mimeData().urls()]
            self.files_dropped.emit([path for path in paths if path.lower().endswith(".csv")])
            event.acceptProposedAction()
            return
        super().dropEvent(event)


class ColorButton(QPushButton):
    color_changed = Signal(str)

    def __init__(self, color: str) -> None:
        super().__init__()
        self.setObjectName("colorButton")
        self.setFixedSize(34, 24)
        self._color = color
        self.clicked.connect(self.choose_color)
        self._refresh()

    @property
    def color(self) -> str:
        return self._color

    def choose_color(self) -> None:
        selected = QColorDialog.getColor(QColor(self._color), self, "Choose color")
        if selected.isValid():
            self._color = selected.name().upper()
            self._refresh()
            self.color_changed.emit(self._color)

    def _refresh(self) -> None:
        self.setToolTip(self._color)
        self.setStyleSheet(
            f"QPushButton#colorButton {{ background: {self._color}; border: 1px solid palette(mid); border-radius: 6px; }}"
        )


class AspectRatioSvgWidget(QWidget):
    """Keep the SVG canvas at its design ratio inside a flexible preview area."""

    def __init__(self, width: int = 1600, height: int = 1000) -> None:
        super().__init__()
        self._ratio = width / height
        self._svg = QSvgWidget(self)

    def load(self, data: QByteArray) -> None:
        self._svg.load(data)

    def renderer(self):  # type: ignore[no-untyped-def]
        return self._svg.renderer()

    def set_aspect_ratio(self, width: int, height: int) -> None:
        self._ratio = width / height
        self._layout_svg()

    def resizeEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        super().resizeEvent(event)
        self._layout_svg()

    def _layout_svg(self) -> None:
        available_width = self.width()
        available_height = self.height()
        if available_width <= 0 or available_height <= 0:
            return
        if available_width / available_height > self._ratio:
            height = available_height
            width = round(height * self._ratio)
        else:
            width = available_width
            height = round(width / self._ratio)
        self._svg.setGeometry(
            (available_width - width) // 2,
            (available_height - height) // 2,
            width,
            height,
        )


class AeroRouteWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("AeroRoute")
        self.resize(1380, 820)
        self.setMinimumSize(1080, 680)
        self.setAcceptDrops(True)
        self._legs: dict[str, ImportedLeg] = {}
        self._render_timer = QTimer(self)
        self._render_timer.setSingleShot(True)
        self._render_timer.setInterval(100)
        self._render_timer.timeout.connect(self.refresh_preview)
        self._build_ui()
        self._apply_native_semantics()
        self._connect_controls()
        self._update_state()

    def _build_ui(self) -> None:
        root = QWidget()
        outer = QVBoxLayout(root)
        outer.setContentsMargins(14, 14, 14, 12)
        outer.setSpacing(10)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.setChildrenCollapsible(False)
        splitter.addWidget(self._make_leg_panel())
        splitter.addWidget(self._make_preview_panel())
        splitter.addWidget(self._make_inspector())
        splitter.setSizes([270, 790, 290])
        splitter.setStretchFactor(1, 1)
        outer.addWidget(splitter, 1)

        footer = QHBoxLayout()
        self.status_label = QLabel()
        self.status_label.setObjectName("status")
        self.export_button = QPushButton("Export SVG…")
        self.export_button.setObjectName("primary")
        footer.addWidget(self.status_label, 1)
        footer.addWidget(self.export_button)
        outer.addLayout(footer)
        self.setCentralWidget(root)

    def _apply_native_semantics(self) -> None:
        """Add hierarchy without overriding the native macOS palette or controls."""

        for label in self.findChildren(QLabel):
            if label.objectName() == "section":
                font = label.font()
                font.setPointSize(11)
                font.setWeight(QFont.Weight.DemiBold)
                font.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 0.5)
                label.setFont(font)
                label.setForegroundRole(QPalette.ColorRole.PlaceholderText)
            elif label.objectName() == "emptyTitle":
                font = label.font()
                font.setPointSize(20)
                font.setWeight(QFont.Weight.DemiBold)
                label.setFont(font)
            elif label.objectName() in {"secondary", "status"}:
                label.setForegroundRole(QPalette.ColorRole.PlaceholderText)
        self.export_button.setDefault(True)

    def _make_leg_panel(self) -> QWidget:
        panel = QFrame()
        panel.setObjectName("panel")
        panel.setFrameShape(QFrame.Shape.NoFrame)
        panel.setMinimumWidth(235)
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(12, 12, 12, 12)
        heading = QHBoxLayout()
        label = QLabel("FLIGHT LEGS")
        label.setObjectName("section")
        self.add_button = QPushButton("Add CSV…")
        heading.addWidget(label)
        heading.addStretch()
        heading.addWidget(self.add_button)
        layout.addLayout(heading)
        hint = QLabel("Drag to reorder. Each leg must connect end to start.")
        hint.setObjectName("secondary")
        hint.setWordWrap(True)
        layout.addWidget(hint)
        self.flight_list = FlightList()
        self.flight_list.setFrameShape(QFrame.Shape.NoFrame)
        layout.addWidget(self.flight_list, 1)
        controls = QHBoxLayout()
        self.remove_button = QPushButton("Remove")
        self.clear_button = QPushButton("Clear")
        controls.addWidget(self.remove_button)
        controls.addWidget(self.clear_button)
        controls.addStretch()
        layout.addLayout(controls)
        return panel

    def _make_preview_panel(self) -> QWidget:
        panel = QFrame()
        panel.setObjectName("panel")
        panel.setFrameShape(QFrame.Shape.NoFrame)
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(8, 8, 8, 8)
        self.preview_stack = QStackedWidget()
        empty = QWidget()
        empty_layout = QVBoxLayout(empty)
        empty_layout.addStretch()
        empty_title = QLabel("Drop Flightradar24 CSV files here")
        empty_title.setObjectName("emptyTitle")
        empty_title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        empty_copy = QLabel("Single flight or ordered end-to-start itinerary")
        empty_copy.setObjectName("secondary")
        empty_copy.setAlignment(Qt.AlignmentFlag.AlignCenter)
        empty_layout.addWidget(empty_title)
        empty_layout.addWidget(empty_copy)
        empty_layout.addStretch()
        self.preview = AspectRatioSvgWidget()
        self.preview.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.preview_stack.addWidget(empty)
        self.preview_stack.addWidget(self.preview)
        layout.addWidget(self.preview_stack)
        return panel

    def _make_inspector(self) -> QWidget:
        panel = QFrame()
        panel.setObjectName("panel")
        panel.setFrameShape(QFrame.Shape.NoFrame)
        panel.setMinimumWidth(270)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        body = QWidget()
        body_layout = QVBoxLayout(body)
        body_layout.setContentsMargins(12, 12, 12, 12)
        body_layout.setSpacing(12)

        heading = QLabel("EXPORT INSPECTOR")
        heading.setObjectName("section")
        body_layout.addWidget(heading)
        form = self._left_aligned_form()
        self.flight_number = QLineEdit()
        self.flight_number.setPlaceholderText("LX188 or ITINERARY")
        self.airport_codes = QLineEdit()
        self.airport_codes.setPlaceholderText("PVG, MUC, CPH, KEF")
        self.airport_names = QLineEdit()
        self.airport_names.setPlaceholderText("Shanghai Pudong, Munich, …")
        self.route_name = QLineEdit()
        self.route_name.setPlaceholderText("Optional subtitle override")
        form.addRow("Title", self.flight_number)
        form.addRow("Airport codes", self.airport_codes)
        form.addRow("Airport names", self.airport_names)
        form.addRow("Route subtitle", self.route_name)
        body_layout.addLayout(form)

        options_label = QLabel("MAP CONTENT")
        options_label.setObjectName("section")
        body_layout.addWidget(options_label)
        self.show_borders = QCheckBox("Country borders")
        self.show_borders.setChecked(True)
        self.show_airports = QCheckBox("Airport labels")
        self.show_airports.setChecked(True)
        self.show_metadata = QCheckBox("Flight metadata")
        self.show_metadata.setChecked(True)
        body_layout.addWidget(self.show_borders)
        body_layout.addWidget(self.show_airports)
        body_layout.addWidget(self.show_metadata)

        output_label = QLabel("OUTPUT")
        output_label.setObjectName("section")
        body_layout.addWidget(output_label)
        output_form = self._left_aligned_form()
        self.width_spin = QSpinBox()
        self.width_spin.setRange(320, 10000)
        self.width_spin.setValue(1600)
        self.height_spin = QSpinBox()
        self.height_spin.setRange(200, 10000)
        self.height_spin.setValue(1000)
        self.scale_spin = QDoubleSpinBox()
        self.scale_spin.setRange(0.1, 100.0)
        self.scale_spin.setDecimals(1)
        self.scale_spin.setSingleStep(1.0)
        self.scale_spin.setValue(10.0)
        self.route_width_spin = QDoubleSpinBox()
        self.route_width_spin.setRange(0.1, 20.0)
        self.route_width_spin.setDecimals(1)
        self.route_width_spin.setValue(1.2)
        output_form.addRow("Design width", self.width_spin)
        output_form.addRow("Design height", self.height_spin)
        output_form.addRow("Output scale", self.scale_spin)
        output_form.addRow("Route width", self.route_width_spin)
        body_layout.addLayout(output_form)

        colors_label = QLabel("COLORS")
        colors_label.setObjectName("section")
        body_layout.addWidget(colors_label)
        colors = self._left_aligned_form()
        self.color_buttons = {
            "Ocean": ColorButton("#B2BAC3"),
            "Land": ColorButton("#D9D9D9"),
            "Route": ColorButton("#183143"),
            "Marker": ColorButton("#E05B45"),
            "Text": ColorButton("#171D21"),
        }
        for name, button in self.color_buttons.items():
            colors.addRow(name, button)
        body_layout.addLayout(colors)
        body_layout.addStretch()
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setWidget(body)
        outer = QVBoxLayout(panel)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(scroll)
        return panel

    @staticmethod
    def _left_aligned_form() -> QFormLayout:
        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignmentFlag.AlignLeft)
        form.setFormAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        form.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.ExpandingFieldsGrow)
        form.setVerticalSpacing(8)
        return form

    def _connect_controls(self) -> None:
        self.add_button.clicked.connect(self.choose_files)
        self.remove_button.clicked.connect(self.remove_selected)
        self.clear_button.clicked.connect(self.clear_files)
        self.export_button.clicked.connect(self.export_svg)
        self.flight_list.files_dropped.connect(self.import_files)
        self.flight_list.order_changed.connect(self._schedule_refresh)
        QShortcut(QKeySequence.StandardKey.Open, self, activated=self.choose_files)
        QShortcut(QKeySequence.StandardKey.Delete, self, activated=self.remove_selected)
        for control in (self.flight_number, self.airport_codes, self.airport_names, self.route_name):
            control.textChanged.connect(self._schedule_refresh)
        for control in (self.show_borders, self.show_airports, self.show_metadata):
            control.toggled.connect(self._schedule_refresh)
        for control in (self.width_spin, self.height_spin, self.route_width_spin):
            control.valueChanged.connect(self._schedule_refresh)
        for button in self.color_buttons.values():
            button.color_changed.connect(self._schedule_refresh)

    def dragEnterEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event) -> None:  # type: ignore[no-untyped-def]
        paths = [url.toLocalFile() for url in event.mimeData().urls()]
        self.import_files([path for path in paths if path.lower().endswith(".csv")])
        event.acceptProposedAction()

    def choose_files(self) -> None:
        paths, _ = QFileDialog.getOpenFileNames(
            self, "Import Flightradar24 CSV", "", "CSV files (*.csv)"
        )
        self.import_files(paths)

    def import_files(self, paths: list[str]) -> None:
        errors: list[str] = []
        first_import = self.flight_list.count() == 0
        for raw_path in paths:
            path = str(Path(raw_path).resolve())
            if path in self._legs:
                continue
            try:
                imported = load_fr24(path)
            except (OSError, TrackDataError) as exc:
                errors.append(f"{Path(path).name}: {exc}")
                continue
            self._legs[path] = imported
            item = QListWidgetItem()
            item.setData(Qt.ItemDataRole.UserRole, path)
            item.setText(
                f"{imported.metadata.flight_number}\n"
                f"{imported.metadata.row_count:,} points  ·  {imported.metadata.callsign or 'no callsign'}"
            )
            item.setToolTip(path)
            self.flight_list.addItem(item)
        if first_import and self.flight_list.count():
            numbers = [leg.metadata.flight_number for leg in self._ordered_legs()]
            self.flight_number.setText(numbers[0] if len(numbers) == 1 else " · ".join(numbers))
        if errors:
            QMessageBox.warning(self, "Some files were not imported", "\n\n".join(errors))
        self._update_state()

    def remove_selected(self) -> None:
        for item in self.flight_list.selectedItems():
            path = item.data(Qt.ItemDataRole.UserRole)
            self._legs.pop(path, None)
            self.flight_list.takeItem(self.flight_list.row(item))
        self._update_state()

    def clear_files(self) -> None:
        self.flight_list.clear()
        self._legs.clear()
        self._update_state()

    def _ordered_legs(self) -> list[ImportedLeg]:
        return [
            self._legs[self.flight_list.item(index).data(Qt.ItemDataRole.UserRole)]
            for index in range(self.flight_list.count())
        ]

    @staticmethod
    def _csv_values(value: str) -> tuple[str, ...]:
        return tuple(part.strip() for part in value.split(",") if part.strip())

    def _render_options(self, *, preview: bool) -> RenderOptions:
        return RenderOptions(
            width=self.width_spin.value(),
            height=self.height_spin.value(),
            scale=1.0 if preview else self.scale_spin.value(),
            show_borders=self.show_borders.isChecked(),
            show_airports=self.show_airports.isChecked(),
            show_flight_number=self.show_metadata.isChecked(),
            flight_number=self.flight_number.text().strip() or None,
            waypoint_codes=self._csv_values(self.airport_codes.text()),
            waypoint_names=self._csv_values(self.airport_names.text()),
            route_name=self.route_name.text().strip() or None,
        )

    def _map_style(self) -> MapStyle:
        return MapStyle(
            ocean=self.color_buttons["Ocean"].color,
            land=self.color_buttons["Land"].color,
            route=self.color_buttons["Route"].color,
            marker=self.color_buttons["Marker"].color,
            text=self.color_buttons["Text"].color,
            route_width=self.route_width_spin.value(),
        )

    def _combined_track(self):  # type: ignore[no-untyped-def]
        legs = self._ordered_legs()
        tracks = [leg.track for leg in legs]
        validate_leg_order(tracks)
        if len(legs) == 1:
            return legs[0].track
        return combine_tracks(
            [leg.metadata.source for leg in legs],
            source_name=self.flight_number.text().strip() or "itinerary",
            validate_continuity=True,
        )

    def _schedule_refresh(self, *_args) -> None:  # type: ignore[no-untyped-def]
        self._render_timer.start()

    def _update_state(self) -> None:
        count = self.flight_list.count()
        self.remove_button.setEnabled(bool(self.flight_list.selectedItems()) or count > 0)
        self.clear_button.setEnabled(count > 0)
        if not count:
            self.preview_stack.setCurrentIndex(0)
            self.export_button.setEnabled(False)
            self.status_label.setText("No files imported")
            return
        self.refresh_preview()

    def refresh_preview(self) -> None:
        if not self.flight_list.count():
            self._update_state()
            return
        try:
            track = self._combined_track()
            svg, stats = build_svg(track, options=self._render_options(preview=True), style=self._map_style())
        except (OSError, TrackDataError, ValueError) as exc:
            self.preview_stack.setCurrentIndex(0)
            self.export_button.setEnabled(False)
            self.status_label.setText(str(exc))
            return
        self.preview.load(QByteArray(svg.encode("utf-8")))
        self.preview.set_aspect_ratio(self.width_spin.value(), self.height_spin.value())
        self.preview_stack.setCurrentIndex(1)
        self.export_button.setEnabled(True)
        legs = self.flight_list.count()
        self.status_label.setText(
            f"{legs} leg{'s' if legs != 1 else ''}  ·  {stats.source_points:,} source points  ·  "
            f"{stats.curve_segments:,} cubic segments"
        )

    def export_svg(self) -> None:
        try:
            track = self._combined_track()
        except (OSError, TrackDataError, ValueError) as exc:
            QMessageBox.warning(self, "Cannot export", str(exc))
            return
        suggested = (self.flight_number.text().strip() or "flight-map").replace(" · ", "-") + ".svg"
        destination, _ = QFileDialog.getSaveFileName(self, "Export SVG", suggested, "SVG image (*.svg)")
        if not destination:
            return
        if not destination.lower().endswith(".svg"):
            destination += ".svg"
        try:
            stats = write_svg(
                track,
                destination,
                options=self._render_options(preview=False),
                style=self._map_style(),
            )
        except (OSError, ValueError) as exc:
            QMessageBox.critical(self, "Export failed", str(exc))
            return
        self.status_label.setText(
            f"Exported {Path(destination).name} with {stats.source_points:,} source points"
        )


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("AeroRoute")
    app.setOrganizationName("AeroRoute")
    window = AeroRouteWindow()
    window.show()
    csv_arguments = [argument for argument in sys.argv[1:] if argument.lower().endswith(".csv")]
    if csv_arguments:
        window.import_files(csv_arguments)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
