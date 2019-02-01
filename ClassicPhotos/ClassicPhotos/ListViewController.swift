/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import CoreImage

let dataSourceURL = URL(string:"http://www.raywenderlich.com/downloads/ClassicPhotosDictionary.plist")!

class ListViewController: UITableViewController {
  var photos: [PhotoRecord] = []
  let pendingOperations = PendingOperations()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    self.title = "Classic Photos"
    
    fetchPhotoDetails()
  }
  
  // MARK: - Table view data source

  override func tableView(_ tableView: UITableView?, numberOfRowsInSection section: Int) -> Int {
    return photos.count
  }
  
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "CellIdentifier", for: indexPath)
    
    //1
    if cell.accessoryView == nil {
      let indicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
      cell.accessoryView = indicator
    }
    let indicator = cell.accessoryView as! UIActivityIndicatorView
    
    //2
    let photoDetails = photos[indexPath.row]
    
    //3
    cell.textLabel?.text = photoDetails.name
    cell.imageView?.image = photoDetails.image
    
    //4
    switch (photoDetails.state) {
    case .filtered:
      indicator.stopAnimating()
    case .failed:
      indicator.stopAnimating()
      cell.textLabel?.text = "Failed to load"
    case .new, .downloaded:
      indicator.startAnimating()
      if !tableView.isDragging && !tableView.isDecelerating {
        startOperations(for: photoDetails, at: indexPath)
      }
    }
    
    return cell
  }
  
  func startOperations(for photoRecord: PhotoRecord, at indexPath: IndexPath) {
    switch (photoRecord.state) {
    case .new:
      startDownload(for: photoRecord, at: indexPath)
    case .downloaded:
      startFiltration(for: photoRecord, at: indexPath)
    default:
      NSLog("do nothing")
    }
  }
  
  func startDownload(for photoRecord: PhotoRecord, at indexPath: IndexPath) {
    //1
    guard pendingOperations.downloadsInProgress[indexPath] == nil else {
      return
    }
    
    //2
    let downloader = ImageDownloader(photoRecord)
    
    //3
    downloader.completionBlock = {
      if downloader.isCancelled {
        return
      }
      
      DispatchQueue.main.async {
        self.pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
        self.tableView.reloadRows(at: [indexPath], with: .fade)
      }
    }
    
    //4
    pendingOperations.downloadsInProgress[indexPath] = downloader
    
    //5
    pendingOperations.downloadQueue.addOperation(downloader)
  }
  
  func startFiltration(for photoRecord: PhotoRecord, at indexPath: IndexPath) {
    guard pendingOperations.filtrationsInProgress[indexPath] == nil else {
      return
    }
    
    let filterer = ImageFiltration(photoRecord)
    filterer.completionBlock = {
      if filterer.isCancelled {
        return
      }
      
      DispatchQueue.main.async {
        self.pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
        self.tableView.reloadRows(at: [indexPath], with: .fade)
      }
    }
    
    pendingOperations.filtrationsInProgress[indexPath] = filterer
    pendingOperations.filtrationQueue.addOperation(filterer)
  }

  
  func fetchPhotoDetails() {
    let request = URLRequest(url: dataSourceURL)
    UIApplication.shared.isNetworkActivityIndicatorVisible = true
    
    // 1
    let task = URLSession.shared.dataTask(with: request) { (data, resonse, error) in
      // 2
      let alertController = UIAlertController(title: "Oops!",
                                              message: "There was an error fetching photo details.",
                                              preferredStyle: .alert)
      let okAction = UIAlertAction(title: "OK", style: .default)
      alertController.addAction(okAction)
      
      if let data = data {
        do {
          // 3
          let datasourceDictionary =
            try PropertyListSerialization.propertyList(from: data,
                                                       options: [],
                                                       format: nil) as! [String: String]
          
          // 4
          for (name, value) in datasourceDictionary {
            let url = URL(string: value)
            if let url = url {
              let photoRecord = PhotoRecord(name: name, url: url)
              self.photos.append(photoRecord)
            }
          }
          
          // 5
          DispatchQueue.main.async {
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            self.tableView.reloadData()
          }
          
          // 6
        } catch {
          DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
          }
        }
      }
      
      // 6
      if error != nil {
        DispatchQueue.main.async {
          UIApplication.shared.isNetworkActivityIndicatorVisible = false
          self.present(alertController, animated: true, completion: nil)
        }
      }
    }
    
    // 7
    task.resume()
  }
  
  override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    //1
    suspendAllOperations()
  }
  
  override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    // 2
    if !decelerate {
      loadImagesForOnscreenCells()
      resumeAllOperations()
    }
  }
  
  override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    // 3
    loadImagesForOnscreenCells()
    resumeAllOperations()
  }

  func suspendAllOperations() {
    pendingOperations.downloadQueue.isSuspended = true
    pendingOperations.filtrationQueue.isSuspended = true
  }
  
  func resumeAllOperations() {
    pendingOperations.downloadQueue.isSuspended = false
    pendingOperations.filtrationQueue.isSuspended = false
  }
  
  func loadImagesForOnscreenCells() {
    //1: Start with an array containing index paths of all the currently visible rows in the table view.
    if let pathsArray = tableView.indexPathsForVisibleRows {
      
      //2: Construct a set of all pending operations by combining all the downloads in progress and all the filters in progress.
      var allPendingOperations = Set(pendingOperations.downloadsInProgress.keys)
      allPendingOperations.formUnion(pendingOperations.filtrationsInProgress.keys)
      
      //3: Construct a set of all index paths with operations to be cancelled. Start with all operations, and then remove the index paths of the visible rows. This will leave the set of operations involving off-screen rows.
      var toBeCancelled = allPendingOperations
      let visiblePaths = Set(pathsArray)
      toBeCancelled.subtract(visiblePaths)
      
      //4: Construct a set of index paths that need their operations started. Start with index paths all visible rows, and then remove the ones where operations are already pending.
      var toBeStarted = visiblePaths
      toBeStarted.subtract(allPendingOperations)
      
      // 5: Loop through those to be cancelled, cancel them, and remove their reference from PendingOperations.
      for indexPath in toBeCancelled {
        if let pendingDownload = pendingOperations.downloadsInProgress[indexPath] {
          pendingDownload.cancel()
        }
        pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
        
        if let pendingFiltration = pendingOperations.filtrationsInProgress[indexPath] {
          pendingFiltration.cancel()
        }
        pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
      }
      
      // 6: Loop through those to be started, and call startOperations(for:at:) for each.
      for indexPath in toBeStarted {
        let recordToProcess = photos[indexPath.row]
        startOperations(for: recordToProcess, at: indexPath)
      }
    }
  }

}
