import UIKit
import VideoKit

class ViewController: UITableViewController {

  // MARK: - Properties

  static let videoURLs: [(URL, Double)] = [
    ("https://giant.gfycat.com/CompleteBareClingfish.mp4", 16.0 / 9.0),
    ("https://giant.gfycat.com/WillingOddballAustraliancurlew.mp4", 16.0 / 9.0),
    ("https://giant.gfycat.com/MediumImpartialAzurewingedmagpie.mp4", 4.0 / 5.0),
    ("https://giant.gfycat.com/MarriedRequiredGrassspider.mp4", 1.0),
    ("https://giant.gfycat.com/PreciousCriminalFruitfly.mp4", 1.0),
    ("https://giant.gfycat.com/WelldocumentedUnkemptLemur.mp4", 636.0 / 392.0),
  ]
    .compactMap { url, aspectRatio in URL(string: url).flatMap { ($0, aspectRatio) } }

  // MARK: - LifeCycle

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.register(Cell.self, forCellReuseIdentifier: "cellIdentifier")
  }

  // MARK: - DataSource

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    Self.videoURLs.count
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cellIdentifier", for: indexPath) as! Cell
    let (videoURL, _) = Self.videoURLs[indexPath.row]
    cell.playerView.set(url: videoURL)
    cell.playerView.play()
    return cell
  }

  // MARK: - Delegate

  override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    let (_, aspectRatio) = Self.videoURLs[indexPath.row]
   return tableView.bounds.width / aspectRatio
  }

}

