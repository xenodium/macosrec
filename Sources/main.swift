/*
 * This file is part of macosrec.
 *
 * Copyright (C) 2023 Álvaro Ramírez https://xenodium.com
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import ArgumentParser
import Quartz

var recorder: WindowRecorder?

signal(SIGINT) { _ in
  recorder?.stop()
  exit(0)
}

struct RecordCommand: ParsableCommand {
  @Flag(help: "List recordable windows")
  var list: Bool = false

  @Option(help: "Take a screenshot")
  var screenshot: String?

  @Option(name: .shortAndLong, help: "Start recording window number.")
  var record: String?

  @Flag(help: "Stop recording.")
  var stop: Bool = false

  mutating func run() throws {
    if list {
      NSWorkspace.shared.printWindowList()
      Darwin.exit(0)
    }

    if let windowNumber = screenshot {
      recorder = WindowRecorder(for: CGWindowID(windowNumber)!)
      recorder?.screenshot()
      Darwin.exit(0)
    }

    if let windowNumber = record {
      if recordingPid() != nil {
        print("Error: Already recording")
        Darwin.exit(1)
      }
      recorder = WindowRecorder(for: CGWindowID(windowNumber)!)
      recorder?.start()
      return
    }

    if stop {
      guard let recordingPid = recordingPid() else {
        print("Error: No recording")
        Darwin.exit(1)
      }
      let result = kill(recordingPid, SIGINT)
      if result != 0 {
        print("Error: Could not stop recording")
        Darwin.exit(1)
      }
      Darwin.exit(0)
    }
  }
}

guard CommandLine.arguments.count > 1 else {
  print("\(RecordCommand.helpMessage())")
  exit(1)
}
RecordCommand.main()
RunLoop.current.run()

struct WindowInfo {
  let app: String
  let title: String
  let number: CGWindowID
}

extension NSWorkspace {
  func printWindowList() {
    for window in allWindows() {
      if window.title.isEmpty {
        print("\(window.number) \(window.app)")
      } else {
        print("\(window.number) \(window.app) - \(window.title)")
      }
    }
  }

  func window(identifiedAs windowNumber: CGWindowID) -> WindowInfo? {
    allWindows().first {
      $0.number == windowNumber
    }
  }

  func allWindows() -> [WindowInfo] {
    var windowInfos = [WindowInfo]()
    let windows =
      CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
    for app in NSWorkspace.shared.runningApplications {
      for window in windows ?? [] {
        if let windowPid = window[kCGWindowOwnerPID as String] as? Int,
          windowPid == app.processIdentifier,
          let number = window[kCGWindowNumber as String] as? Int,
          let appName = app.localizedName
        {
          let title = window[kCGWindowName as String] as? String ?? ""
          windowInfos.append(WindowInfo(app: appName, title: title, number: CGWindowID(number)))
        }
      }
    }
    return windowInfos
  }
}

class WindowRecorder {
  private let window: WindowInfo
  private let fps = 10.0
  private var timer: Timer?
  private var images = [CGImage]()

  var interval: Double {
    1.0 / fps
  }

  init(for windowNumber: CGWindowID) {
    guard let foundWindow = NSWorkspace.shared.window(identifiedAs: windowNumber) else {
      print("Error: window not found")
      exit(1)
    }

    self.window = foundWindow
  }

  func screenshot() {
    do {
      guard let image = windowImage() else {
        print("Error: No window image")
        exit(1)
      }
      guard let url = getDesktopFileURL(suffix: window.app, ext: ".png") else {
        print("Error: could craft URL to screenshot")
        exit(1)
      }
      guard let data = image.pngData(compressionFactor: 1) else {
        print("Error: No png data")
        exit(1)
      }
      try data.write(to: url)
      print("\(url.path)")
      exit(0)
    } catch {
      print("Error: \(error.localizedDescription)")
      exit(1)
    }
  }

  func start() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(
      withTimeInterval: TimeInterval(interval), repeats: true,
      block: { [weak self] _ in
        guard let self = self else {
          print("Error: No recorder")
          exit(1)
        }
        guard
          let image = windowImage()
        else {
          print("Error: No image from window")
          exit(1)
        }
        DispatchQueue.global(qos: .default).sync {
          guard let resizedImage = image.resize(compressionFactor: 1.0, scale: 0.7) else {
            print("Error: Could not resize frame")
            exit(1)
          }
          self.images.append(resizedImage)
        }
      })
  }

  func windowImage() -> CGImage? {
    return CGWindowListCreateImage(
      CGRect.null, CGWindowListOption.optionIncludingWindow, self.window.number,
      CGWindowImageOption.boundsIgnoreFraming)
  }

  func stop() {
    print("Saving...")
    timer?.invalidate()

    guard let url = getDesktopFileURL(suffix: window.app, ext: ".gif") else {
      print("Error: could craft URL to animation")
      exit(1)
    }

    guard
      let destinationGIF = CGImageDestinationCreateWithURL(
        url as NSURL, kUTTypeGIF, images.count, nil)
    else {
      print("Error: No destination GIF")
      exit(1)
    }

    CGImageDestinationSetProperties(
      destinationGIF,
      [
        kCGImagePropertyGIFDictionary as String:
          [
            kCGImagePropertyGIFLoopCount as String: 0
              // kCGImagePropertyGIFHasGlobalColorMap as String: false,
              // kCGImagePropertyColorModel as String: kCGImagePropertyColorModelRGB,
          ] as [String: Any]
      ] as CFDictionary
    )
    images.reverse()

    while self.images.count > 0 {
      let image = self.images.popLast()!
      CGImageDestinationAddImage(
        destinationGIF, image,
        [
          kCGImagePropertyGIFDictionary as String:
            [(kCGImagePropertyGIFDelayTime as String): 1.0 / fps]
        ] as CFDictionary)
    }
    if CGImageDestinationFinalize(destinationGIF) {
      print("\(url.path)")
      exit(0)
    } else {
      print("Error: could not save")
      exit(1)
    }
  }
}

extension CGImage {
  func pngData(compressionFactor: Float) -> Data? {
    NSBitmapImageRep(cgImage: self).representation(
      using: .png, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: compressionFactor])
  }

  func resize(compressionFactor: Float, scale: Float) -> CGImage? {
    guard
      let pngData = pngData(compressionFactor: compressionFactor)
    else {
      return nil
    }
    guard let data = CGImageSourceCreateWithData(pngData as CFData, nil) else {
      return nil
    }
    var maxSideLength = width
    if height > width {
      maxSideLength = height
    }
    maxSideLength = Int(Float(maxSideLength) * scale)
    let options: [String: Any] = [
      kCGImageSourceThumbnailMaxPixelSize as String: maxSideLength,
      kCGImageSourceCreateThumbnailFromImageAlways as String: true,
      kCGImageSourceCreateThumbnailWithTransform as String: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(data, 0, options as CFDictionary)!
  }
}

func recordingPid() -> pid_t? {
  let name = ProcessInfo.processInfo.processName
  let task = Process()
  task.launchPath = "/bin/ps"
  task.arguments = ["-A", "-o", "pid,comm"]

  let pipe = Pipe()
  task.standardOutput = pipe
  task.launch()

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  let output = String(data: data, encoding: String.Encoding.utf8)

  let lines = output!.components(separatedBy: "\n")
  for line in lines {
    if line.contains(name) && !line.contains("defunct") {
      let components = line.components(separatedBy: " ")
      let values = components.filter { $0 != "" }
      let found = pid_t(values[0])
      if found != getpid() {
        return found
      }
    }
  }

  return nil
}

func getDesktopFileURL(suffix: String, ext: String) -> URL? {
  let dateFormatter = DateFormatter()
  dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
  let timestamp = dateFormatter.string(from: Date())
  let fileName = timestamp + "-" + suffix + ext

  guard var desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
  else { return nil }
  desktopURL.appendPathComponent(fileName)

  return desktopURL
}
