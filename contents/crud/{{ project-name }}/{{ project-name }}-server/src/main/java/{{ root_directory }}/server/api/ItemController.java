package {{ root_package }}.server.api;

import {{ group_id }}.persistence.Item;
import {{ group_id }}.persistence.ItemRepository;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * The standard CRUD surface (p6m standards S2): a name-derived, versioned base path over the
 * {@code { id, displayName }} entity with conventional status semantics
 * (POST 201 / GET 200 / PUT 200 / DELETE 204 / 404 for unknown ids).
 */
@RestController
@RequestMapping("/api/v1/{{ prefix-name }}s")
public class ItemController {

    public record ItemRequest(String displayName) {
    }

    public record ItemResponse(String id, String displayName) {
    }

    private final ItemRepository repository;

    public ItemController(ItemRepository repository) {
        this.repository = repository;
    }

    private static ItemResponse toResponse(Item item) {
        return new ItemResponse(item.getId(), item.getDisplayName());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ItemResponse create(@RequestBody ItemRequest request) {
        return toResponse(repository.save(new Item(request.displayName())));
    }

    @GetMapping
    public List<ItemResponse> list() {
        return repository.findAll().stream().map(ItemController::toResponse).toList();
    }

    @GetMapping("/{id}")
    public ResponseEntity<ItemResponse> get(@PathVariable("id") String id) {
        return repository.findById(id)
                .map(item -> ResponseEntity.ok(toResponse(item)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PutMapping("/{id}")
    public ResponseEntity<ItemResponse> update(@PathVariable("id") String id, @RequestBody ItemRequest request) {
        return repository.findById(id)
                .map(item -> {
                    item.setDisplayName(request.displayName());
                    return ResponseEntity.ok(toResponse(repository.save(item)));
                })
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable("id") String id) {
        if (!repository.existsById(id)) {
            return ResponseEntity.notFound().build();
        }
        repository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
