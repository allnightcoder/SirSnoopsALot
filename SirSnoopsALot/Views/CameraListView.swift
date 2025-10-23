import SwiftUI

enum ListMode {
    case normal
    case sorting
    case selecting
}

struct CameraListView: View {
    @Binding var selectedCamera: CameraConfig?
    @State private var showingAddCamera = false
    @State private var showingFrigateImport = false
    @StateObject private var cameraManager = CameraManager.shared
    @State private var listMode: ListMode = .normal
    @State private var selectedCameraIds: Set<UUID> = []
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List(selection: $selectedCamera) {
            ForEach(cameraManager.cameras, id: \.id) { camera in
                let isSelected = selectedCameraIds.contains(camera.id)

                if case .selecting = listMode {
                    // Selection mode: tap to select
                    Button(action: {
                        toggleSelection(for: camera.id)
                    }) {
                        CameraListItemView(
                            camera: camera,
                            isInSortMode: false,
                            isInSelectionMode: true,
                            isSelected: isSelected,
                            onToggleSelection: { toggleSelection(for: camera.id) }
                        )
                    }
                    .buttonStyle(.plain)
                } else if case .sorting = listMode {
                    // Sort mode: reordering only
                    CameraListItemView(
                        camera: camera,
                        isInSortMode: true,
                        isInSelectionMode: false,
                        isSelected: false,
                        onToggleSelection: {}
                    )
                } else {
                    // Normal mode: navigation
                    NavigationLink(value: camera) {
                        CameraListItemView(
                            camera: camera,
                            isInSortMode: false,
                            isInSelectionMode: false,
                            isSelected: false,
                            onToggleSelection: {}
                        )
                    }
                }
            }
            .onMove { source, destination in
                cameraManager.moveCamera(from: source, to: destination)
            }
        }
        .navigationTitle("Cameras")
        .listStyle(.sidebar)
        .toolbar {
            // Normal mode: Add and Edit menus
            if case .normal = listMode {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            showingAddCamera = true
                        }) {
                            Label("Add Manually", systemImage: "plus.circle")
                        }

                        Button(action: {
                            showingFrigateImport = true
                        }) {
                            Label("Import from Frigate", systemImage: "arrow.down.doc")
                        }
                    } label: {
                        Label("Add Camera", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            withAnimation {
                                listMode = .sorting
                            }
                        }) {
                            Label("Reorder", systemImage: "arrow.up.arrow.down")
                        }

                        Button(action: {
                            withAnimation {
                                listMode = .selecting
                                selectedCameraIds.removeAll()
                            }
                        }) {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        .disabled(cameraManager.cameras.isEmpty)
                    } label: {
                        Label("Edit", systemImage: "ellipsis.circle")
                    }
                    .disabled(cameraManager.cameras.isEmpty)
                }
            }

            // Sorting mode button
            if case .sorting = listMode {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        withAnimation {
                            listMode = .normal
                        }
                    }) {
                        Label("Done", systemImage: "checkmark")
                    }
                }
            }

            // Selection mode buttons
            if case .selecting = listMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        withAnimation {
                            listMode = .normal
                            selectedCameraIds.removeAll()
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete (\(selectedCameraIds.count))", systemImage: "trash")
                    }
                    .disabled(selectedCameraIds.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingAddCamera) {
            AddCameraView()
        }
        .sheet(isPresented: $showingFrigateImport) {
            ImportFromFrigateView()
        }
        .confirmationDialog(
            "Delete \(selectedCameraIds.count) Camera\(selectedCameraIds.count == 1 ? "" : "s")",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedCameraIds.count) Camera\(selectedCameraIds.count == 1 ? "" : "s")", role: .destructive) {
                deleteSelectedCameras()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \(selectedCameraIds.count) camera\(selectedCameraIds.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .environment(\.editMode, .constant(listMode == .sorting ? .active : .inactive))
        .onChange(of: listMode) { _, newValue in
            if newValue != .sorting {
                // Sort mode was disabled, ensure changes are saved
                cameraManager.saveCameras()
            }
        }
    }

    private func toggleSelection(for cameraId: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedCameraIds.contains(cameraId) {
                selectedCameraIds.remove(cameraId)
            } else {
                selectedCameraIds.insert(cameraId)
            }
        }
    }

    private func deleteSelectedCameras() {
        withAnimation {
            cameraManager.deleteCameras(selectedCameraIds)
            selectedCameraIds.removeAll()
            listMode = .normal
        }
    }
}

#Preview {
    NavigationStack {
        CameraListView(
            selectedCamera: .constant(nil)
        )
    }
} 
